package com.qsw.rdesk.wake
import org.junit.Assert.*
import org.junit.Test
class WakePacketTest {
    @Test fun encodesBroadcastMagicPacket() {
        val packet=WakePacket.encode("02:11:22:33:44:55")
        assertEquals(102,packet.size)
        assertArrayEquals(ByteArray(6){0xff.toByte()},packet.copyOfRange(0,6))
        repeat(16){assertArrayEquals(byteArrayOf(2,17,34,51,68,85),packet.copyOfRange(6+it*6,12+it*6))}
    }
    @Test fun rejectsMulticastAndMalformed() {
        listOf("01:11:22:33:44:55","ff:ff:ff:ff:ff:ff","00:00:00:00:00:00","02:11:22:33:44","02:11:22:33:44:gg").forEach {
            try {WakePacket.encode(it);fail("accepted invalid MAC")}catch(_:IllegalArgumentException){}
        }
    }
}
