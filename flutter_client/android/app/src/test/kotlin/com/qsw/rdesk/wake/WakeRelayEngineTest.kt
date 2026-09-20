package com.qsw.rdesk.wake
import org.junit.Assert.*
import org.junit.Test
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

class WakeRelayEngineTest {
    private val job=WakeJob("request","pc","02:11:22:33:44:55",1,30000)
    private class Clock:WakeClock {var now=0L;override fun elapsedMs()=now;override fun waitMs(ms:Long){now+=ms}}
    private class Journal:WakeJournal {
        val rows=mutableMapOf<String,Boolean?>()
        override fun reserve(id:String):Boolean {if(rows.containsKey(id))return false;rows[id]=null;return true}
        override fun finish(id:String,sent:Boolean){rows[id]=sent}
        override fun outcome(id:String)=rows[id]
    }
    private class Sender:WakeSender {val packets=mutableListOf<ByteArray>();override fun send(packet:ByteArray){packets.add(packet)};override fun close(){}}
    private open class Transport(val job:WakeJob):WakeTransport {
        var sent=false;override fun poll():WakeJob?=job;override fun authorize(job:WakeJob)=SendPermit(2000)
        override fun result(job:WakeJob,sent:Boolean,errorCode:String?){this.sent=sent}
        override fun disable(){};override fun cancel(){}
    }
    @Test fun sendsBoundedBatchAndDuplicateDoesNotSendAgain() {
        val sender=Sender();val t=Transport(job);val e=WakeRelayEngine(t,sender,Clock(),Journal())
        e.step();assertEquals(3,sender.packets.size);assertEquals(102,sender.packets[0].size);assertTrue(t.sent)
        e.step();assertEquals(3,sender.packets.size)
    }
    @Test fun stopWhilePollIsPendingNeverSendsLateJob() {
        val entered=CountDownLatch(1);val release=CountDownLatch(1)
        val t=object:Transport(job){override fun poll():WakeJob {entered.countDown();release.await(2,TimeUnit.SECONDS);return job}}
        val sender=Sender();val e=WakeRelayEngine(t,sender,Clock(),Journal())
        val thread=Thread{e.step()};thread.start();assertTrue(entered.await(1,TimeUnit.SECONDS));e.stop();release.countDown();thread.join(2000)
        assertTrue(sender.packets.isEmpty());assertFalse(thread.isAlive)
    }
    @Test fun expiredJobDoesNotSend() {
        val sender=Sender();val e=WakeRelayEngine(Transport(job.copy(remainingMs=0)),sender,Clock(),Journal());e.step();assertTrue(sender.packets.isEmpty())
    }
    @Test fun authorizationRoundTripConsumesPermitLifetime() {
        val clock=Clock();val t=object:Transport(job){override fun authorize(job:WakeJob):SendPermit{clock.now+=3000;return SendPermit(2000)}}
        val sender=Sender();WakeRelayEngine(t,sender,clock,Journal()).step();assertTrue(sender.packets.isEmpty())
    }
    @Test fun receiptNetworkFailureRetriesReceiptWithoutAnotherPacket() {
        var results=0
        val t=object:Transport(job){override fun result(job:WakeJob,sent:Boolean,errorCode:String?){results++;if(results==1)throw java.io.IOException("offline");super.result(job,sent,errorCode)}}
        val sender=Sender();val e=WakeRelayEngine(t,sender,Clock(),Journal())
        try{e.step();fail("expected receipt failure")}catch(_:java.io.IOException){}
        assertEquals(3,sender.packets.size);e.step();assertEquals(3,sender.packets.size);assertTrue(t.sent)
    }
    @Test fun stopBetweenPacketsPreventsRemainingBatch() {
        lateinit var engine:WakeRelayEngine
        val clock=object:WakeClock{override fun elapsedMs()=0L;override fun waitMs(ms:Long){engine.stop()}}
        val sender=Sender();val t=Transport(job)
        engine=WakeRelayEngine(t,sender,clock,Journal());engine.step()
        assertEquals(1,sender.packets.size);assertFalse(t.sent)
    }
}
