package com.example.rdesk

import android.app.Activity
import android.app.KeyguardManager
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.media.projection.MediaProjectionManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.view.WindowManager
import android.widget.Toast
import androidx.core.app.NotificationManagerCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val permissionRequestCode = 4102
    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        RdeskApplicationHolder.applicationContext = applicationContext

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.example.rdesk/android_host",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getScreenCaptureState" -> result.success(ScreenCaptureStore.toMap())
                "getLatestCapturedFrame" -> result.success(ScreenCaptureStore.frameToMap())
                "requestScreenCapturePermission" -> requestScreenCapturePermission(result)
                "startScreenCaptureService" -> startScreenCaptureService(result)
                "stopScreenCaptureService" -> stopScreenCaptureService(result)
                "showRemoteTapIndicator" -> showRemoteTapIndicator(call, result)
                "performRemoteLongPress" -> performRemoteLongPress(call, result)
                "performRemoteDrag" -> performRemoteDrag(call, result)
                "performRemoteTextInput" -> performRemoteTextInput(call, result)
                "setClipboardText" -> setClipboardText(call, result)
                "getClipboardText" -> getClipboardText(result)
                "performRemoteAction" -> performRemoteAction(call, result)
                "openAccessibilitySettings" -> openAccessibilitySettings(result)
                "openOverlaySettings" -> openOverlaySettings(result)
                "openNotificationSettings" -> openNotificationSettings(result)
                "openBatteryOptimizationSettings" -> openBatteryOptimizationSettings(result)
                "openAppDetailsSettings" -> openAppDetailsSettings(result)
                "wakeScreen" -> wakeScreen(result)
                "setKeepScreenOn" -> setKeepScreenOn(call, result)
                else -> result.notImplemented()
            }
        }
    }

    private fun requestScreenCapturePermission(result: MethodChannel.Result) {
        if (pendingResult != null) {
            result.error("busy", "已有录屏授权请求正在处理中", null)
            return
        }

        val projectionManager =
            getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        pendingResult = result
        ScreenCaptureStore.state = ScreenCaptureState.REQUESTING
        @Suppress("DEPRECATION")
        startActivityForResult(projectionManager.createScreenCaptureIntent(), permissionRequestCode)
    }

    private fun startScreenCaptureService(result: MethodChannel.Result) {
        if (!ScreenCaptureStore.hasPermission()) {
            result.success(ScreenCaptureStore.toMap("尚未授予录屏权限"))
            return
        }

        val intent = Intent(this, ScreenCaptureService::class.java).apply {
            action = ScreenCaptureService.ACTION_START
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
        ScreenCaptureStore.state = ScreenCaptureState.RUNNING
        result.success(ScreenCaptureStore.toMap("前台录屏服务已启动"))
    }

    private fun stopScreenCaptureService(result: MethodChannel.Result) {
        val intent = Intent(this, ScreenCaptureService::class.java).apply {
            action = ScreenCaptureService.ACTION_STOP
        }
        startService(intent)
        ScreenCaptureStore.state =
            if (ScreenCaptureStore.hasPermission()) ScreenCaptureState.READY else ScreenCaptureState.IDLE
        result.success(ScreenCaptureStore.toMap("前台录屏服务已停止"))
    }

    private fun showRemoteTapIndicator(call: MethodCall, result: MethodChannel.Result) {
        val x = call.argument<Double>("x") ?: 0.0
        val y = call.argument<Double>("y") ?: 0.0
        val dispatched =
            RdeskAccessibilityService.instance?.performTap(x, y) ?: false
        runOnUiThread {
            Toast.makeText(
                this,
                if (dispatched) {
                    "已执行远程点击 ${(x * 100).toInt()}%, ${(y * 100).toInt()}%"
                } else {
                    "收到远程点击 ${(x * 100).toInt()}%, ${(y * 100).toInt()}%（未启用无障碍）"
                },
                Toast.LENGTH_SHORT,
            ).show()
        }
        result.success(null)
    }

    private fun openAccessibilitySettings(result: MethodChannel.Result) {
        startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
        result.success(null)
    }

    private fun openOverlaySettings(result: MethodChannel.Result) {
        val intent = Intent(
            Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
            Uri.parse("package:$packageName"),
        )
        startActivity(intent)
        result.success(null)
    }

    private fun openNotificationSettings(result: MethodChannel.Result) {
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
            }
        } else {
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                data = Uri.parse("package:$packageName")
            }
        }
        startActivity(intent)
        result.success(null)
    }

    private fun openBatteryOptimizationSettings(result: MethodChannel.Result) {
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
            !pm.isIgnoringBatteryOptimizations(packageName)
        ) {
            Intent(
                Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                Uri.parse("package:$packageName"),
            )
        } else {
            Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
        }
        startActivity(intent)
        result.success(null)
    }

    private fun openAppDetailsSettings(result: MethodChannel.Result) {
        startActivity(
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                data = Uri.parse("package:$packageName")
            },
        )
        result.success(null)
    }

    private fun performRemoteAction(call: MethodCall, result: MethodChannel.Result) {
        val action = call.argument<String>("action") ?: ""
        val performed = RdeskAccessibilityService.instance?.performAction(action) ?: false
        if (!performed) {
            runOnUiThread {
                Toast.makeText(
                    this,
                    "未执行动作 $action（请确认已启用无障碍控制）",
                    Toast.LENGTH_SHORT,
                ).show()
            }
        }
        result.success(performed)
    }

    private fun performRemoteLongPress(call: MethodCall, result: MethodChannel.Result) {
        val x = call.argument<Double>("x") ?: 0.0
        val y = call.argument<Double>("y") ?: 0.0
        val performed = RdeskAccessibilityService.instance?.performLongPress(x, y) ?: false
        if (!performed) {
            runOnUiThread {
                Toast.makeText(
                    this,
                    "未执行长按（请确认已启用无障碍控制）",
                    Toast.LENGTH_SHORT,
                ).show()
            }
        }
        result.success(performed)
    }

    private fun performRemoteDrag(call: MethodCall, result: MethodChannel.Result) {
        val startX = call.argument<Double>("startX") ?: 0.0
        val startY = call.argument<Double>("startY") ?: 0.0
        val endX = call.argument<Double>("endX") ?: 0.0
        val endY = call.argument<Double>("endY") ?: 0.0
        val performed =
            RdeskAccessibilityService.instance?.performDrag(startX, startY, endX, endY) ?: false
        if (!performed) {
            runOnUiThread {
                Toast.makeText(
                    this,
                    "未执行拖拽（请确认已启用无障碍控制）",
                    Toast.LENGTH_SHORT,
                ).show()
            }
        }
        result.success(performed)
    }

    private fun performRemoteTextInput(call: MethodCall, result: MethodChannel.Result) {
        val text = call.argument<String>("text") ?: ""
        val performed = RdeskAccessibilityService.instance?.performTextInput(text) ?: false
        if (!performed) {
            runOnUiThread {
                Toast.makeText(
                    this,
                    "未写入文本（请先让 Android 输入框获得焦点并启用无障碍控制）",
                    Toast.LENGTH_SHORT,
                ).show()
            }
        }
        result.success(performed)
    }

    private fun setClipboardText(call: MethodCall, result: MethodChannel.Result) {
        val text = call.argument<String>("text") ?: ""
        val clipboardManager =
            getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        clipboardManager.setPrimaryClip(ClipData.newPlainText("rdesk", text))
        result.success(true)
    }

    private fun getClipboardText(result: MethodChannel.Result) {
        val clipboardManager =
            getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        val text = clipboardManager.primaryClip?.getItemAt(0)?.coerceToText(this)?.toString()
        result.success(text)
    }

    @Suppress("DEPRECATION")
    private fun wakeScreen(result: MethodChannel.Result) {
        try {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager

            // 1. Acquire wake lock to turn screen ON
            if (!pm.isInteractive) {
                val wakeLock = pm.newWakeLock(
                    PowerManager.SCREEN_BRIGHT_WAKE_LOCK
                        or PowerManager.ACQUIRE_CAUSES_WAKEUP
                        or PowerManager.ON_AFTER_RELEASE,
                    "rdesk:wake-screen"
                )
                wakeLock.acquire(5000L) // hold for 5 seconds, then auto-release
            }

            // 2. Dismiss keyguard (works only if no secure lock is set)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val km = getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
                km.requestDismissKeyguard(this, object : KeyguardManager.KeyguardDismissCallback() {
                    override fun onDismissSucceeded() {}
                    override fun onDismissCancelled() {}
                    override fun onDismissError() {}
                })
            } else {
                window.addFlags(
                    WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD
                        or WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED
                        or WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
                )
            }

            // 3. Ensure our activity window also stays on
            runOnUiThread {
                window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            }

            result.success(true)
        } catch (e: Exception) {
            result.success(false)
        }
    }

    private fun setKeepScreenOn(call: MethodCall, result: MethodChannel.Result) {
        val enabled = call.argument<Boolean>("enabled") ?: true
        runOnUiThread {
            if (enabled) {
                window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            } else {
                window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            }
        }
        result.success(true)
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != permissionRequestCode) {
            return
        }

        val channelResult = pendingResult
        pendingResult = null

        if (resultCode == Activity.RESULT_OK && data != null) {
            ScreenCaptureStore.permissionResultCode = resultCode
            ScreenCaptureStore.permissionData = Intent(data)
            ScreenCaptureStore.state = ScreenCaptureState.READY
            channelResult?.success(ScreenCaptureStore.toMap("录屏权限已授予"))
        } else {
            ScreenCaptureStore.state = ScreenCaptureState.IDLE
            channelResult?.success(ScreenCaptureStore.toMap("用户取消了录屏授权"))
        }
    }
}

enum class ScreenCaptureState {
    IDLE,
    REQUESTING,
    READY,
    RUNNING,
    ERROR,
}

object RdeskApplicationHolder {
    lateinit var applicationContext: Context
}

object ScreenCaptureStore {
    var permissionResultCode: Int? = null
    var permissionData: Intent? = null
    var state: ScreenCaptureState = ScreenCaptureState.IDLE
    @Volatile var latestFrame: ByteArray? = null
    @Volatile var latestFrameWidth: Int = 0
    @Volatile var latestFrameHeight: Int = 0
    @Volatile var latestFrameTimestampMs: Long = 0L

    fun hasPermission(): Boolean = permissionResultCode != null && permissionData != null

    fun toMap(message: String? = null): Map<String, Any?> {
        val context = RdeskApplicationHolder.applicationContext
        val powerManager = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        return mapOf(
            "state" to state.name.lowercase(),
            "hasPermission" to hasPermission(),
            "isRunning" to (state == ScreenCaptureState.RUNNING),
            "accessibilityEnabled" to (RdeskAccessibilityService.instance != null),
            "overlayEnabled" to Settings.canDrawOverlays(context),
            "notificationsEnabled" to NotificationManagerCompat.from(context).areNotificationsEnabled(),
            "batteryOptimizationIgnored" to (
                Build.VERSION.SDK_INT < Build.VERSION_CODES.M ||
                    powerManager.isIgnoringBatteryOptimizations(context.packageName)
                ),
            "manufacturer" to Build.MANUFACTURER,
            "message" to message,
        )
    }

    fun frameToMap(): Map<String, Any?> =
        mapOf(
            "bytes" to latestFrame,
            "width" to latestFrameWidth,
            "height" to latestFrameHeight,
            "timestampMs" to latestFrameTimestampMs,
        )
}
