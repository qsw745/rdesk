package com.qsw.rdesk.wake

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import java.net.DatagramSocket
import java.net.DatagramPacket
import java.net.Inet4Address
import java.net.InetAddress

/**
 * The home LAN as the helper was enabled on: Wi-Fi interface plus its single private IPv4 address.
 * IPv6 privacy addresses, address lifetimes and routes rotate on dual-stack home broadband, so they
 * must not decide whether the helper is still on the same network.
 */
data class LanIdentity(val iface:String,val address:InetAddress,val prefix:Int) {
    val broadcast:InetAddress get() {
        val value=address.address.fold(0){acc,b->(acc shl 8) or (b.toInt() and 255)} or (-1 shl (32-prefix)).inv()
        return InetAddress.getByAddress(byteArrayOf((value ushr 24).toByte(),(value ushr 16).toByte(),(value ushr 8).toByte(),value.toByte()))
    }
    companion object {
        fun of(iface:String?,addresses:List<Pair<InetAddress,Int>>):LanIdentity? {
            val v4=addresses.filter{(a,p)->a is Inet4Address && a.isSiteLocalAddress && p in 1..30}
            if(iface.isNullOrEmpty()||v4.size!=1)return null
            return LanIdentity(iface,v4[0].first,v4[0].second)
        }
    }
}

class WakeNetwork(context:Context,expected:LanIdentity?=null):WakeSender {
    private val manager=context.getSystemService(ConnectivityManager::class.java)
    val network:Network=manager.allNetworks.singleOrNull {
        manager.getNetworkCapabilities(it)?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)==true
    }?:throw IllegalStateException("wifi_required")
    val identity:LanIdentity=current()?.takeIf{expected==null||it==expected}
        ?:throw IllegalStateException(if(expected==null)"ipv4_required" else "network_changed")
    private var socket:DatagramSocket?=null
    private fun current():LanIdentity? {
        val props=manager.getLinkProperties(network)?:return null
        return LanIdentity.of(props.interfaceName,props.linkAddresses.map{it.address to it.prefixLength})
    }
    fun valid():Boolean=manager.getNetworkCapabilities(network)?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)==true && runCatching{current()==identity}.getOrDefault(false)
    override fun send(packet:ByteArray) {
        check(valid()){"network_changed"}
        val sock=socket?:DatagramSocket().also{it.broadcast=true;network.bindSocket(it);socket=it}
        sock.send(DatagramPacket(packet,packet.size,identity.broadcast,9))
    }
    override fun close(){socket?.close();socket=null}
}
