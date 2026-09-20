package com.qsw.rdesk.wake

import android.net.Network
import org.json.JSONObject
import java.net.URL
import java.net.HttpURLConnection
import javax.net.ssl.HttpsURLConnection

class WakeHttpTransport(private val config:WakeConfig,private val network:Network):WakeTransport {
    private val gate=Any()
    @Volatile private var stopped=false
    @Volatile private var active:HttpURLConnection?=null
    private fun send(path:String,body:JSONObject=JSONObject()):JSONObject? {
        val base=URL(config.endpoint);require(base.protocol=="https" && base.userInfo==null)
        val connection=network.openConnection(URL(base,path)) as HttpsURLConnection
        synchronized(gate){if(stopped){connection.disconnect();throw java.io.IOException("stopped")};active=connection}
        try {
            connection.connectTimeout=5000;connection.readTimeout=12000;connection.instanceFollowRedirects=false;connection.requestMethod="POST"
            connection.setRequestProperty("Authorization","Bearer ${config.token}");connection.setRequestProperty("Content-Type","application/json");connection.doOutput=true
            connection.outputStream.use{it.write(body.toString().toByteArray(Charsets.UTF_8))}
            val status=connection.responseCode
            val stream=if(status in 200..299)connection.inputStream else connection.errorStream
            val bytes=stream?.use {
                val output=java.io.ByteArrayOutputStream();val buffer=ByteArray(4096)
                while(true){val n=it.read(buffer);if(n<0)break;output.write(buffer,0,n);if(output.size()>262144)break}
                output.toByteArray()
            }?:ByteArray(0)
            if(bytes.size>262144)throw java.io.IOException("response_too_large")
            val json=if(bytes.isEmpty())null else runCatching{JSONObject(String(bytes,Charsets.UTF_8))}.getOrNull()
            if(status !in 200..299)throw WakeHttpException(status,json?.optString("code")?:"network")
            if(status!=204 && json==null)throw java.io.IOException("invalid_response")
            return json
        }finally{synchronized(gate){if(active===connection)active=null};connection.disconnect()}
    }
    override fun poll():WakeJob? {
        val j=send("/api/wake/agents/${config.agentId}/poll")?:return null
        return WakeJob(j.getString("id"),j.getString("target_id"),j.getString("mac"),j.getLong("revision"),j.getLong("remaining_ms"))
    }
    override fun authorize(job:WakeJob):SendPermit=SendPermit(send("/api/wake/requests/${job.id}/authorize-send")!!.getLong("remaining_ms"))
    override fun result(job:WakeJob,sent:Boolean,errorCode:String?) {send("/api/wake/requests/${job.id}/result",JSONObject().put("phase",if(sent)"sent" else "failed").put("error_code",errorCode?:JSONObject.NULL))}
    override fun disable(){send("/api/wake/agents/${config.agentId}/disable")}
    override fun cancel(){synchronized(gate){stopped=true;active?.disconnect();active=null}}
}
