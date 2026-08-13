package com.qsw.rdesk

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.PixelFormat
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
import java.io.ByteArrayOutputStream
import kotlin.math.roundToInt

class ScreenCaptureService : Service() {
    private var mediaProjection: MediaProjection? = null
    private var imageReader: ImageReader? = null
    private var virtualDisplay: VirtualDisplay? = null
    private var captureThread: HandlerThread? = null
    private var captureHandler: Handler? = null
    private var cpuWakeLock: PowerManager.WakeLock? = null

    /// 当前持有的唤醒锁是否是亮屏级别，用于判断开关变化后需不需要换锁。
    private var wakeLockHoldsScreen = false
    private var lastEncodedFrameAtMs = 0L

    /// 投屏存活看门狗。
    ///
    /// 系统（尤其 Android 14+ 的后台投屏回收）可能在不触发 onStop 的情况下拆掉
    /// MediaProjection：此时前台服务仍在、types 仍声明 mediaProjection，
    /// 但 ImageReader 再也收不到图像，`latestFrame` 会永远停在最后一张。
    /// 上层若继续把这张死图当作有效画面推送，观看端看到的就是定格的屏幕——
    /// 比直接断开更难排查。
    ///
    /// 静止画面同样不产生新图像，所以「多久没收到图」不能作为判据；
    /// 这里改用 VirtualDisplay 是否仍然有效来判断，与屏幕是否变化无关。
    private val watchdogHandler = Handler(Looper.getMainLooper())
    private val watchdogRunnable = object : Runnable {
        override fun run() {
            if (!isProjectionAlive()) {
                onProjectionLost()
                return
            }
            // 心跳：证明持有投屏的实例还活着，供 startCapture 判断标记是否新鲜。
            ScreenCaptureStore.projectionHeartbeatMs = SystemClock.elapsedRealtime()
            // 顺带跟随「保持屏幕常亮」开关的变化：用户在运行期间切换开关时，
            // 靠这一跳应用，省掉往服务里传实例引用的那套管线。
            applyWakeLock()
            watchdogHandler.postDelayed(this, WATCHDOG_INTERVAL_MS)
        }
    }

    /// 按「保持屏幕常亮」开关选择唤醒锁级别。
    ///
    /// 关：PARTIAL —— 只保 CPU，屏幕可以熄，采集与命令轮询照常。
    /// 开：SCREEN_BRIGHT —— 屏幕不灭，锁屏不出现，避开会终止投屏的
    ///     STOP_REASON_KEYGUARD 策略。
    /// 已废弃的 SCREEN_BRIGHT_WAKE_LOCK 仍是唯一能在后台服务里保持亮屏的手段，
    /// FLAG_KEEP_SCREEN_ON 需要前台 Activity，托管时 App 通常在后台。
    @Suppress("DEPRECATION")
    private fun applyWakeLock() {
        val wantScreenOn = ScreenCaptureStore.keepScreenAwake
        if (cpuWakeLock != null && wantScreenOn == wakeLockHoldsScreen) {
            return
        }

        cpuWakeLock?.let { if (it.isHeld) it.release() }

        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        val level = if (wantScreenOn) {
            PowerManager.SCREEN_BRIGHT_WAKE_LOCK
        } else {
            PowerManager.PARTIAL_WAKE_LOCK
        }
        cpuWakeLock = pm.newWakeLock(
            level,
            if (wantScreenOn) "rdesk:capture-screen" else "rdesk:capture-cpu",
        ).apply { acquire() }
        wakeLockHoldsScreen = wantScreenOn
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        return when (intent?.action) {
            ACTION_STOP -> {
                stopCapture()
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
                START_NOT_STICKY
            }

            ACTION_START, null -> {
                createNotificationChannel()
                startForeground(NOTIFICATION_ID, buildNotification())
                startCapture()
                START_STICKY
            }

            else -> START_NOT_STICKY
        }
    }

    override fun onDestroy() {
        stopCapture()
        super.onDestroy()
    }

    @Suppress("DEPRECATION")
    private fun startCapture() {
        if (!ScreenCaptureStore.hasPermission()) {
            ScreenCaptureStore.state = ScreenCaptureState.ERROR
            return
        }

        // 已有活动投屏就不要再取第二个：同一个 resultData 再取一次会让系统作废
        // 前一个，刚建好的采集当场失效。判断用进程级标记，因为服务实例重建后
        // mediaProjection 字段会归零，只看它会漏判。
        val heartbeatAgeMs =
            SystemClock.elapsedRealtime() - ScreenCaptureStore.projectionHeartbeatMs
        val otherInstanceAlive = ScreenCaptureStore.projectionActive &&
            heartbeatAgeMs < PROJECTION_HEARTBEAT_STALE_MS
        if (mediaProjection != null || otherInstanceAlive) {
            ScreenCaptureStore.state = ScreenCaptureState.RUNNING
            return
        }

        // 标记还在但心跳早停：持有投屏的实例已经不在了，而授权 token 已被它用掉，
        // 无法静默重建。如实要求重新授权，别谎报可用。
        if (ScreenCaptureStore.projectionActive) {
            ScreenCaptureStore.projectionActive = false
            ScreenCaptureStore.invalidatePermission()
            ScreenCaptureStore.state = ScreenCaptureState.ERROR
            return
        }

        applyWakeLock()

        val projectionManager =
            getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        val resultCode = ScreenCaptureStore.permissionResultCode ?: run {
            ScreenCaptureStore.state = ScreenCaptureState.ERROR
            return
        }
        val data = ScreenCaptureStore.permissionData ?: run {
            ScreenCaptureStore.state = ScreenCaptureState.ERROR
            return
        }

        val metrics = resources.displayMetrics
        val width = metrics.widthPixels
        val height = metrics.heightPixels
        val densityDpi = metrics.densityDpi
        lastEncodedFrameAtMs = 0L

        captureThread = HandlerThread("rdesk-screen-capture").also { it.start() }
        captureHandler = Handler(captureThread!!.looper)

        imageReader = ImageReader.newInstance(width, height, PixelFormat.RGBA_8888, 2).apply {
            setOnImageAvailableListener({ reader ->
                val image = reader.acquireLatestImage() ?: return@setOnImageAvailableListener
                try {
                    val elapsedNow = SystemClock.elapsedRealtime()
                    if (elapsedNow - lastEncodedFrameAtMs < ScreenCaptureStore.minFrameIntervalMs) {
                        return@setOnImageAvailableListener
                    }
                    lastEncodedFrameAtMs = elapsedNow

                    val plane = image.planes.firstOrNull() ?: return@setOnImageAvailableListener
                    val pixelStride = plane.pixelStride
                    val rowStride = plane.rowStride
                    val rowPadding = rowStride - pixelStride * width
                    val bitmapWidth = width + rowPadding / pixelStride

                    val bitmap =
                        Bitmap.createBitmap(bitmapWidth, height, Bitmap.Config.ARGB_8888).apply {
                            copyPixelsFromBuffer(plane.buffer)
                        }
                    val cropped = Bitmap.createBitmap(bitmap, 0, 0, width, height)
                    bitmap.recycle()

                    val maxDimension = maxOf(width, height).toDouble()
                    val scale =
                        minOf(1.0, ScreenCaptureStore.maxFrameLongEdgePx.toDouble() / maxDimension)
                    val outputWidth = (width * scale).roundToInt().coerceAtLeast(1)
                    val outputHeight = (height * scale).roundToInt().coerceAtLeast(1)
                    val encoded =
                        if (outputWidth == width && outputHeight == height) {
                            cropped
                        } else {
                            Bitmap.createScaledBitmap(cropped, outputWidth, outputHeight, true)
                        }
                    if (encoded !== cropped) {
                        cropped.recycle()
                    }

                    val stream = ByteArrayOutputStream()
                    encoded.compress(Bitmap.CompressFormat.JPEG, ScreenCaptureStore.jpegQuality, stream)
                    encoded.recycle()

                    ScreenCaptureStore.latestFrame = stream.toByteArray()
                    ScreenCaptureStore.latestFrameWidth = outputWidth
                    ScreenCaptureStore.latestFrameHeight = outputHeight
                    ScreenCaptureStore.latestFrameTimestampMs = System.currentTimeMillis()
                    ScreenCaptureStore.state = ScreenCaptureState.RUNNING
                } catch (_: Throwable) {
                    ScreenCaptureStore.state = ScreenCaptureState.ERROR
                } finally {
                    image.close()
                }
            }, captureHandler)
        }

        mediaProjection =
            projectionManager.getMediaProjection(resultCode, Intent(data))?.apply {
                registerCallback(
                    object : MediaProjection.Callback() {
                        override fun onStop() {
                            // 用户或系统主动停止投屏，与看门狗走同一条清理路径。
                            watchdogHandler.post { onProjectionLost() }
                        }
                    },
                    captureHandler,
                )
            }

        virtualDisplay =
            mediaProjection?.createVirtualDisplay(
                "rdesk-screen-capture",
                width,
                height,
                densityDpi,
                DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
                imageReader?.surface,
                null,
                captureHandler,
            )

        ScreenCaptureStore.projectionActive = virtualDisplay != null
        ScreenCaptureStore.projectionHeartbeatMs = SystemClock.elapsedRealtime()
        ScreenCaptureStore.state = ScreenCaptureState.RUNNING
        watchdogHandler.removeCallbacks(watchdogRunnable)
        watchdogHandler.postDelayed(watchdogRunnable, WATCHDOG_INTERVAL_MS)
    }

    /// VirtualDisplay 被系统释放后 display 会失效，这与屏幕是否静止无关，
    /// 因此可以作为投屏存活的可靠判据。
    private fun isProjectionAlive(): Boolean =
        mediaProjection != null && virtualDisplay?.display?.isValid == true

    /// 投屏丢失：必须清掉缓存帧，否则上层会把这张死图当作有效画面持续推送。
    ///
    /// 系统终止投屏（锁屏 STOP_REASON_KEYGUARD、后台回收）时授权 token 同时作废，
    /// 因此这里要一并 invalidatePermission()：
    ///   1. 留着死 token，下一次启动采集会抛 SecurityException 使服务启动失败，
    ///      表现为 App 崩溃重启；
    ///   2. hasPermission() 若仍为 true，stopCapture() 末尾会把状态改写成 READY，
    ///      把「投屏已死」伪装成「随时可用」，上层于是继续按在线对待。
    private fun onProjectionLost() {
        ScreenCaptureStore.latestFrame = null
        ScreenCaptureStore.latestFrameWidth = 0
        ScreenCaptureStore.latestFrameHeight = 0
        ScreenCaptureStore.invalidatePermission()
        stopCapture()
        ScreenCaptureStore.state = ScreenCaptureState.ERROR
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun stopCapture() {
        watchdogHandler.removeCallbacks(watchdogRunnable)
        ScreenCaptureStore.projectionActive = false

        // 清空缓存帧，避免服务停止后仍有旧画面被继续上传。
        ScreenCaptureStore.latestFrame = null
        ScreenCaptureStore.latestFrameWidth = 0
        ScreenCaptureStore.latestFrameHeight = 0

        virtualDisplay?.release()
        virtualDisplay = null

        imageReader?.setOnImageAvailableListener(null, null)
        imageReader?.close()
        imageReader = null

        val projection = mediaProjection
        mediaProjection = null
        projection?.stop()

        captureThread?.quitSafely()
        captureThread = null
        captureHandler = null

        // Release CPU wake lock
        cpuWakeLock?.let {
            if (it.isHeld) it.release()
        }
        cpuWakeLock = null
        wakeLockHoldsScreen = false

        if (ScreenCaptureStore.state == ScreenCaptureState.RUNNING ||
            ScreenCaptureStore.state == ScreenCaptureState.ERROR
        ) {
            ScreenCaptureStore.state =
                if (ScreenCaptureStore.hasPermission()) ScreenCaptureState.READY else ScreenCaptureState.IDLE
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }
        val manager = getSystemService(NotificationManager::class.java)
        val channel =
            NotificationChannel(
                CHANNEL_ID,
                "RDesk 屏幕共享",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "保持 Android 被控端录屏服务处于活动状态"
            }
        manager.createNotificationChannel(channel)
    }

    private fun buildNotification(): Notification {
        val builder =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(this, CHANNEL_ID)
            } else {
                Notification.Builder(this)
            }

        return builder
            .setContentTitle("RDesk 屏幕共享")
            .setContentText("正在采集 Android 屏幕预览")
            .setSmallIcon(android.R.drawable.presence_video_online)
            .setOngoing(true)
            .build()
    }

    companion object {
        const val ACTION_START = "com.qsw.rdesk.action.START_CAPTURE"
        const val ACTION_STOP = "com.qsw.rdesk.action.STOP_CAPTURE"
        private const val WATCHDOG_INTERVAL_MS = 5_000L

        /// 心跳超过此时长即认为持有投屏的实例已不在。取看门狗间隔的三倍余量。
        private const val PROJECTION_HEARTBEAT_STALE_MS = 15_000L
        private const val CHANNEL_ID = "rdesk_screen_capture"
        private const val NOTIFICATION_ID = 2201
    }
}
