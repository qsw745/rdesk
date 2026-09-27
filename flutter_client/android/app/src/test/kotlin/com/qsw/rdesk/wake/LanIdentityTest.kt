package com.qsw.rdesk.wake
import org.junit.Assert.*
import org.junit.Test
import java.net.InetAddress

class LanIdentityTest {
    private fun ip(s:String)=InetAddress.getByName(s)
    private val home=listOf(ip("192.168.31.20") to 24,ip("fe80::1") to 64,ip("240e:3b0:1::a") to 64,ip("240e:3b0:1::b") to 64)

    @Test fun ipv6RotationDoesNotChangeHomeLan() {
        val before=LanIdentity.of("wlan0",home)
        val nextDay=LanIdentity.of("wlan0",listOf(ip("192.168.31.20") to 24,ip("fe80::1") to 64,ip("240e:3b1:9::c") to 64))
        assertNotNull(before);assertEquals(before,nextDay)
        assertEquals("192.168.31.255",before!!.broadcast.hostAddress)
    }
    @Test fun differentAddressPrefixOrInterfaceIsAnotherNetwork() {
        val before=LanIdentity.of("wlan0",home)
        assertNotEquals(before,LanIdentity.of("wlan0",listOf(ip("192.168.31.21") to 24)))
        assertNotEquals(before,LanIdentity.of("wlan0",listOf(ip("192.168.31.20") to 16)))
        assertNotEquals(before,LanIdentity.of("wlan1",listOf(ip("192.168.31.20") to 24)))
    }
    @Test fun requiresExactlyOnePrivateIpv4() {
        assertNull(LanIdentity.of("wlan0",listOf(ip("240e:3b0:1::a") to 64)))
        assertNull(LanIdentity.of("wlan0",listOf(ip("8.8.8.8") to 24)))
        assertNull(LanIdentity.of("wlan0",listOf(ip("192.168.1.2") to 24,ip("10.0.0.2") to 8)))
        assertNull(LanIdentity.of(null,listOf(ip("192.168.1.2") to 24)))
        assertNull(LanIdentity.of("wlan0",listOf(ip("192.168.1.2") to 31)))
    }
}
