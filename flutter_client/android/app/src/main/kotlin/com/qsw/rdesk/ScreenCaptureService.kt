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
            watchdogHandler.postDelayed(this, WATCHDOG_INTERVAL_MS)
        }
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

        if (mediaProjection != null) {
            ScreenCaptureStore.state = ScreenCaptureState.RUNNING
            return
        }

        // Acquire a partial wake lock to keep CPU alive even when screen is off.
        // This ensures frame capture and command polling continue working.
        if (cpuWakeLock == null) {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            cpuWakeLock = pm.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "rdesk:capture-cpu"
            ).apply { acquire() }
        }

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

        ScreenCaptureStore.state = ScreenCaptureState.RUNNING
        watchdogHandler.removeCallbacks(watchdogRunnable)
        watchdogHandler.postDelayed(watchdogRunnable, WATCHDOG_INTERVAL_MS)
    }

    /// VirtualDisplay 被系统释放后 display 会失效，这与屏幕是否静止无关，
    /// 因此可以作为投屏存活的可靠判据。
    private fun isProjectionAlive(): Boolean =
        mediaProjection != null && virtualDisplay?.display?.isValid == true

    /// 投屏丢失：必须清掉缓存帧，否则上层会把这张死图当作有效画面持续推送。
    private fun onProjectionLost() {
        ScreenCaptureStore.latestFrame = null
        ScreenCaptureStore.latestFrameWidth = 0
        ScreenCaptureStore.latestFrameHeight = 0
        ScreenCaptureStore.state = ScreenCaptureState.ERROR
        stopCapture()
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun stopCapture() {
        watchdogHandler.removeCallbacks(watchdogRunnable)

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
        private const val CHANNEL_ID = "rdesk_screen_capture"
        private const val NOTIFICATION_ID = 2201
    }
}
