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
        fun status():Map<String,Any?> = mapOf("enabled" to (instance?.let{it.running&&it.config!=null}==true),"networkReady" to (instance?.network?.valid()==true),"lastPollAt" to lastPollAt,"errorCode" to lastError,"agentId" to instance?.config?.agentId,"endpoint" to instance?.config?.endpoint,"ownerId" to instance?.config?.ownerId)
    }
    private var engine:WakeRelayEngine?=null
    @Volatile private var network:WakeNetwork?=null
    @Volatile private var config:WakeConfig?=null
    @Volatile private var running=false
    private val executor=Executors.newSingleThreadExecutor()
    private val clock=object:WakeClock{override fun elapsedMs()=SystemClock.elapsedRealtime();override fun waitMs(ms:Long){Thread.sleep(ms)}}
    private fun notification(paused:Boolean):Notification {
        val stop=PendingIntent.getService(this,NOTIFICATION,Intent(this,WakeRelayService::class.java).setAction(STOP),PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val open=PendingIntent.getActivity(this,NOTIFICATION,Intent(this,MainActivity::class.java),PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        return NotificationCompat.Builder(this,"rdesk_wake").setSmallIcon(R.mipmap.ic_launcher).setContentTitle("RDesk 开机助手")
            .setContentText(if(paused)"已离开家庭 Wi-Fi，回到同一网络后自动继续" else "通过家中 Wi-Fi 接收开机请求").setContentIntent(open).setOngoing(true).addAction(0,"停止",stop).build()
    }
    private fun showPaused(paused:Boolean)=runCatching{getSystemService(NotificationManager::class.java).notify(NOTIFICATION,notification(paused))}
    private fun connect(net:WakeNetwork,loaded:WakeConfig,store:WakeRelayStore):WakeRelayEngine? = synchronized(this) {
        if(!running){net.close();return null}
        network=net;WakeRelayEngine(WakeHttpTransport(loaded,net.network),net,clock,store).also{engine=it}
    }
    /** Nothing is polled or sent while away; only the same Wi-Fi interface and private IPv4 address resume. */
    private fun awaitSameLan(expected:LanIdentity):WakeNetwork? {
        var delay=1000L
        while(running) {
            try{Thread.sleep(delay)}catch(_:InterruptedException){return null}
            runCatching{WakeNetwork(this,expected)}.getOrNull()?.let{return it}
            delay=(delay*2).coerceAtMost(15000)
        }
        return null
    }
    override fun onBind(intent:Intent?)=null
    override fun onStartCommand(intent:Intent?,flags:Int,startId:Int):Int {
        if(intent?.action==STOP){stopNow();stopSelf();return START_NOT_STICKY}
        if(!desired||intent?.getLongExtra("generation",-1)!=generation){stopSelf();return START_NOT_STICKY}
        if(engine!=null)return START_NOT_STICKY
        instance=this;running=true
        val manager=getSystemService(NotificationManager::class.java)
        if(Build.VERSION.SDK_INT>=26)manager.createNotificationChannel(NotificationChannel("rdesk_wake","远程开机助手",NotificationManager.IMPORTANCE_LOW))
        try {
            if(Build.VERSION.SDK_INT>=29)startForeground(NOTIFICATION,notification(false),ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE) else startForeground(NOTIFICATION,notification(false))
            val store=WakeRelayStore(this);val loaded=store.load()?:throw IllegalStateException("configuration_missing")
            config=loaded
            val first=connect(WakeNetwork(this),loaded,store)?:return START_NOT_STICKY
            lastError=null
            executor.execute {
                var worker:WakeRelayEngine=first;var failures=0
                while(!worker.stopped) {
                    val current=network?:break
                    if(!current.valid()){
                        lastError="network_paused";showPaused(true);worker.stop()
                        worker=awaitSameLan(current.identity)?.let{connect(it,loaded,store)}?:break
                        lastError=null;failures=0;showPaused(false);continue
                    }
                    val lock=getSystemService(PowerManager::class.java).newWakeLock(PowerManager.PARTIAL_WAKE_LOCK,"rdesk:wake-request")
                    try {lock.acquire(20000);worker.step();lastPollAt=System.currentTimeMillis();lastError=null;failures=0}
                    catch(e:Exception){
                        if(worker.stopped)continue
                        lastError=if(e is WakeHttpException)e.code else "network"
                        if(e is WakeHttpException && e.status in listOf(401,403,404)){handlerStop();break}
                        failures=(failures+1).coerceAtMost(4)
                        try{Thread.sleep((1000L shl (failures-1)).coerceAtMost(15000)+Random.nextLong(250))}catch(_:InterruptedException){break}
                    } finally {if(lock.isHeld)lock.release()}
                }
            }
        }catch(e:Exception){lastError=e.message?.takeIf{it in listOf("wifi_required","ipv4_required","network_changed","configuration_missing")}?:"start_failed";halt(true)}
        return START_NOT_STICKY
    }
    private fun handlerStop(){Handler(Looper.getMainLooper()).post{if(instance===this){desired=false;generation++;halt(true)}}}
    fun halt(revoke:Boolean) {
        synchronized(this){running=false;engine?.stop();engine=null}
        val oldConfig=config;val oldNetwork=network
        config=null;network=null
        runCatching{WakeRelayStore(this).clear()}
        if(revoke&&oldConfig!=null&&oldNetwork!=null){Thread{runCatching{WakeHttpTransport(oldConfig,oldNetwork.network).disable()}}.start()}
        if(instance===this)instance=null
        stopForeground(STOP_FOREGROUND_REMOVE);stopSelf()
    }
    override fun onDestroy(){running=false;engine?.stop();executor.shutdownNow();if(instance===this){instance=null;desired=false;generation++};super.onDestroy()}
}
