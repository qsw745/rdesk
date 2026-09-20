package com.qsw.rdesk.wake

data class WakeJob(val id:String,val targetId:String,val mac:String,val revision:Long,val remainingMs:Long)
data class SendPermit(val remainingMs:Long)
interface WakeTransport { fun poll():WakeJob?; fun authorize(job:WakeJob):SendPermit; fun result(job:WakeJob,sent:Boolean,errorCode:String?); fun disable(); fun cancel() }
interface WakeSender { fun send(packet:ByteArray); fun close() }
interface WakeClock { fun elapsedMs():Long; fun waitMs(ms:Long) }
interface WakeJournal { fun reserve(id:String):Boolean; fun finish(id:String,sent:Boolean); fun outcome(id:String):Boolean? }
class WakeRelayEngine(val transport:WakeTransport,val sender:WakeSender,val clock:WakeClock,val journal:WakeJournal) {
    private val gate=Any()
    @Volatile var stopped=false; private set
    private var pending:Triple<WakeJob,Boolean,String?>?=null
    fun step() {
        if(stopped)return
        if(pending!=null){flush();return}
        val pollStart=clock.elapsedMs()
        val job=transport.poll()?:return
        if(stopped)return
        val deadline=pollStart+job.remainingMs
        if(clock.elapsedMs()>=deadline)return
        if(!journal.reserve(job.id)) {
            pending=Triple(job,journal.outcome(job.id)==true,"execution_uncertain");flush();return
        }
        val permitStart=clock.elapsedMs()
        val permit=transport.authorize(job)
        val sendDeadline=minOf(deadline,permitStart+permit.remainingMs)
        if(stopped)return
        if(clock.elapsedMs()>=sendDeadline){pending=Triple(job,false,"permit_expired");flush();return}
        try {
            val packet=WakePacket.encode(job.mac)
            repeat(3) { i ->
                synchronized(gate) {
                    if(stopped)return
                    check(clock.elapsedMs()<sendDeadline){"permit_expired"}
                    sender.send(packet)
                }
                if(i<2)clock.waitMs(200)
            }
            journal.finish(job.id,true);pending=Triple(job,true,null)
        } catch(e:Exception) {
            if(stopped)return
            journal.finish(job.id,false);pending=Triple(job,false,"send_failed")
        }
        flush()
    }
    private fun flush() {
        val value=pending?:return
        if(stopped)return
        try {transport.result(value.first,value.second,value.third);pending=null}
        catch(e:WakeHttpException){if(e.status in listOf(401,404,409,410))pending=null;throw e}
    }
    fun stop() {
        synchronized(gate){stopped=true;sender.close()}
        transport.cancel()
    }
}
class WakeHttpException(val status:Int,val code:String):java.io.IOException(code)
