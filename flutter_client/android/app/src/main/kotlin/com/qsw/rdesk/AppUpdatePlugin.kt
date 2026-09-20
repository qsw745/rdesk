package com.qsw.rdesk

import android.app.Activity
import android.content.ClipData
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest

object AppUpdatePlugin {
    @Suppress("DEPRECATION")
    private fun signerSet(info: PackageInfo): Set<String> {
        val signatures = if (Build.VERSION.SDK_INT >= 28) {
            info.signingInfo?.apkContentsSigners
        } else info.signatures
        return signatures?.map { digest(it.toByteArray()) }?.toSet() ?: emptySet()
    }
    private fun digest(bytes: ByteArray) = MessageDigest.getInstance("SHA-256")
        .digest(bytes).joinToString("") { "%02x".format(it) }

    @Suppress("DEPRECATION")
    fun register(activity: Activity, engine: FlutterEngine) {
        var installing = false
        MethodChannel(engine.dartExecutor.binaryMessenger, "com.qsw.rdesk/app_update")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openInstallSettings" -> try {
                        if (Build.VERSION.SDK_INT >= 26) activity.startActivity(Intent(
                            Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                            Uri.parse("package:${activity.packageName}")))
                        result.success(null)
                    } catch (_: Exception) { result.error("settings", "无法打开安装来源设置", null) }
                    "install" -> {
                        if (installing) { result.error("busy", "正在验证安装包", null); return@setMethodCallHandler }
                        val path = call.argument<String>("path")
                        val expectedHash = call.argument<String>("sha256")
                        val expectedSize = call.argument<Number>("bytes")?.toLong()
                        if (path == null || expectedHash == null || expectedSize == null) {
                            result.error("invalid", "安装包参数无效", null); return@setMethodCallHandler
                        }
                        installing = true
                        Thread {
                            try {
                                val file = File(path).canonicalFile
                                val root = File(activity.cacheDir, "rdesk-updates").canonicalFile
                                require(file.path.startsWith(root.path + File.separator) &&
                                    file.extension == "apk" && file.isFile && file.length() == expectedSize &&
                                    expectedSize in 1..(512L * 1024 * 1024))
                                val hash = MessageDigest.getInstance("SHA-256")
                                file.inputStream().use { input ->
                                    val buffer = ByteArray(65536)
                                    while (true) { val count = input.read(buffer); if (count < 0) break; hash.update(buffer, 0, count) }
                                }
                                require(hash.digest().joinToString("") { "%02x".format(it) } == expectedHash)
                                val flags = if (Build.VERSION.SDK_INT >= 28) PackageManager.GET_SIGNING_CERTIFICATES else PackageManager.GET_SIGNATURES
                                val pm = activity.packageManager
                                val archive = requireNotNull(pm.getPackageArchiveInfo(file.path, flags))
                                val installed = pm.getPackageInfo(activity.packageName, flags)
                                require(archive.packageName == activity.packageName)
                                val incomingCode = if (Build.VERSION.SDK_INT >= 28) archive.longVersionCode else archive.versionCode.toLong()
                                val installedCode = if (Build.VERSION.SDK_INT >= 28) installed.longVersionCode else installed.versionCode.toLong()
                                require(incomingCode > installedCode)
                                val signers = signerSet(installed)
                                require(signers.isNotEmpty() && signers == signerSet(archive))
                                activity.runOnUiThread {
                                    installing = false
                                    try {
                                        if (Build.VERSION.SDK_INT >= 26 && !pm.canRequestPackageInstalls()) {
                                            result.success("permission_required")
                                        } else {
                                            val uri = FileProvider.getUriForFile(activity, "${activity.packageName}.updates", file)
                                            activity.startActivity(Intent(Intent.ACTION_VIEW).apply {
                                                setDataAndType(uri, "application/vnd.android.package-archive")
                                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                                clipData = ClipData.newRawUri("RDesk 更新", uri)
                                            })
                                            result.success("opened")
                                        }
                                    } catch (_: Exception) { result.error("installer", "无法打开系统安装程序", null) }
                                }
                            } catch (_: Exception) {
                                activity.runOnUiThread {
                                    installing = false
                                    result.error("invalid_package", "安装包校验失败，必须使用同签名的更高版本", null)
                                }
                            }
                        }.start()
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
