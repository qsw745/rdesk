package com.qsw.rdesk.wake

import android.app.Activity
import android.content.Intent
import android.os.Build
import android.provider.Settings
import androidx.core.app.NotificationManagerCompat
import io.flutter.plugin.common.MethodChannel
import io.flutter.embedding.engine.FlutterEngine
import java.net.URI

object WakeRelayPlugin {
    fun register(activity:Activity,engine:FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger,"com.qsw.rdesk/wake_agent").setMethodCallHandler{call,result->
            try {
                when(call.method){
                    "status"->result.success(WakeRelayService.status())
                    "stop"->{WakeRelayService.stopNow();WakeRelayStore(activity).clear();activity.stopService(Intent(activity,WakeRelayService::class.java));result.success(null)}
                    "openBatterySettings"->{activity.startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS));result.success(null)}
                    "start"->{
                        check(NotificationManagerCompat.from(activity).areNotificationsEnabled()){"notifications_required"}
                        val endpoint=call.argument<String>("endpoint")?:error("https_required")
                        val uri=URI(endpoint);require(uri.scheme=="https"&&uri.host!=null&&uri.userInfo==null){"https_required"}
                        val id=call.argument<String>("agentId")?:error("invalid_agent")
                        val ownerId=call.argument<String>("ownerId")?:error("invalid_owner")
                        val token=call.argument<String>("token")?:error("invalid_agent")
                        require(Regex("^[0-9a-f]{32}$").matches(id)&&Regex("^[0-9a-f]{64}$").matches(token)){"invalid_agent"}
                        WakeNetwork(activity).close()
                        WakeRelayService.stopNow()
                        WakeRelayStore(activity).save(WakeConfig(endpoint,id,token,ownerId))
                        WakeRelayService.desired=true;WakeRelayService.generation++;WakeRelayService.lastError=null
                        val intent=Intent(activity,WakeRelayService::class.java).putExtra("generation",WakeRelayService.generation)
                        if(Build.VERSION.SDK_INT>=26)activity.startForegroundService(intent) else activity.startService(intent)
                        result.success(null)
                    }
                    else->result.notImplemented()
                }
            }catch(_:Exception){if(call.method=="start"){WakeRelayService.desired=false;WakeRelayService.generation++;runCatching{WakeRelayStore(activity).clear()}};result.error("wake_agent_error","无法启动开机助手，请确认 Wi-Fi、通知权限和后台运行设置",null)}
        }
    }
}
