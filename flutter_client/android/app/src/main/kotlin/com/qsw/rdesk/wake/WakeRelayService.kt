package com.qsw.rdesk.wake

import android.app.*
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.*
import androidx.core.app.NotificationCompat
import com.qsw.rdesk.MainActivity
import com.qsw.rdesk.R
import java.util.concurrent.Executors
import kotlin.random.Random

class WakeRelayService:Service() {
    companion object {
        @Volatile var desired=false
        @Volatile var generation=0L
        @Volatile var instance:WakeRelayService?=null
        @Volatile var lastError:String?=null
        @Volatile var lastPollAt=0L
        private const val NOTIFICATION=7391
        const val STOP="com.qsw.rdesk.WAKE_STOP"
        fun stopNow(){desired=false;generation++;instance?.halt(true)}
        fun status():Map<String,Any?> = mapOf("enabled" to (instance?.engine?.stopped==false),"networkReady" to (instance?.network?.valid()==true),"lastPollAt" to lastPollAt,"errorCode" to lastError,"agentId" to instance?.config?.agentId,"endpoint" to instance?.config?.endpoint,"ownerId" to instance?.config?.ownerId)
    }
    private var engine:WakeRelayEngine?=null
    private var network:WakeNetwork?=null
    private var config:WakeConfig?=null
    private val executor=Executors.newSingleThreadExecutor()
    override fun onBind(intent:Intent?)=null
    override fun onStartCommand(intent:Intent?,flags:Int,startId:Int):Int {
        if(intent?.action==STOP){stopNow();stopSelf();return START_NOT_STICKY}
        if(!desired||intent?.getLongExtra("generation",-1)!=generation){stopSelf();return START_NOT_STICKY}
        if(engine!=null)return START_NOT_STICKY
        instance=this
        val manager=getSystemService(NotificationManager::class.java)
        if(Build.VERSION.SDK_INT>=26)manager.createNotificationChannel(NotificationChannel("rdesk_wake","远程开机助手",NotificationManager.IMPORTANCE_LOW))
        val stop=PendingIntent.getService(this,NOTIFICATION,Intent(this,WakeRelayService::class.java).setAction(STOP),PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val open=PendingIntent.getActivity(this,NOTIFICATION,Intent(this,MainActivity::class.java),PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val notification=NotificationCompat.Builder(this,"rdesk_wake").setSmallIcon(R.mipmap.ic_launcher).setContentTitle("RDesk 开机助手")
            .setContentText("通过家中 Wi-Fi 接收开机请求").setContentIntent(open).setOngoing(true).addAction(0,"停止",stop).build()
        try {
        if(Build.VERSION.SDK_INT>=29)startForeground(NOTIFICATION,notification,ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE) else startForeground(NOTIFICATION,notification)
            val store=WakeRelayStore(this);val loaded=store.load()?:throw IllegalStateException("configuration_missing")
            val selected=WakeNetwork(this);network=selected;config=loaded
            val transport=WakeHttpTransport(loaded,selected.network)
            val clock=object:WakeClock{override fun elapsedMs()=SystemClock.elapsedRealtime();override fun waitMs(ms:Long){Thread.sleep(ms)}}
            val worker=WakeRelayEngine(transport,selected,clock,store);engine=worker;lastError=null
            executor.execute {
                var failures=0
                while(!worker.stopped) {
                    if(!selected.valid()){lastError="network_changed";handlerStop();break}
                    val lock=getSystemService(PowerManager::class.java).newWakeLock(PowerManager.PARTIAL_WAKE_LOCK,"rdesk:wake-request")
                    try {lock.acquire(20000);worker.step();lastPollAt=System.currentTimeMillis();lastError=null;failures=0}
                    catch(e:Exception){
                        if(worker.stopped)break
                        lastError=if(e is WakeHttpException)e.code else "network"
                        if(e is WakeHttpException && e.status in listOf(401,403,404)){handlerStop();break}
                        failures=(failures+1).coerceAtMost(4)
                        try{Thread.sleep((1000L shl (failures-1)).coerceAtMost(15000)+Random.nextLong(250))}catch(_:InterruptedException){break}
                    } finally {if(lock.isHeld)lock.release()}
                }
            }
        }catch(e:Exception){lastError=e.message?.takeIf{it in listOf("wifi_required","network_changed","configuration_missing")}?:"start_failed";halt(true)}
        return START_NOT_STICKY
    }
    private fun handlerStop(){Handler(Looper.getMainLooper()).post{if(instance===this){desired=false;generation++;halt(true)}}}
    fun halt(revoke:Boolean) {
        engine?.stop();engine=null
        val oldConfig=config;val oldNetwork=network
        config=null;network=null
        runCatching{WakeRelayStore(this).clear()}
        if(revoke&&oldConfig!=null&&oldNetwork!=null){Thread{runCatching{WakeHttpTransport(oldConfig,oldNetwork.network).disable()}}.start()}
        if(instance===this)instance=null
        stopForeground(STOP_FOREGROUND_REMOVE);stopSelf()
    }
    override fun onDestroy(){engine?.stop();executor.shutdownNow();if(instance===this){instance=null;desired=false;generation++};super.onDestroy()}
}
