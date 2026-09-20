package com.qsw.rdesk.wake

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import java.net.DatagramSocket
import java.net.DatagramPacket
import java.net.Inet4Address
import java.net.InetAddress

class WakeNetwork(context:Context):WakeSender {
    private val manager=context.getSystemService(ConnectivityManager::class.java)
    val network:Network=manager.allNetworks.singleOrNull {
        manager.getNetworkCapabilities(it)?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)==true
    }?:throw IllegalStateException("wifi_required")
    private val initial=signature()
    private var socket:DatagramSocket?=null
    private fun signature():String {
        val props=manager.getLinkProperties(network)?:throw IllegalStateException("network_changed")
        return props.linkAddresses.joinToString()+"|"+props.routes.joinToString()
    }
    fun valid():Boolean=manager.getNetworkCapabilities(network)?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)==true && runCatching{signature()==initial}.getOrDefault(false)
    override fun send(packet:ByteArray) {
        check(valid()){"network_changed"}
        val links=manager.getLinkProperties(network)!!.linkAddresses.filter{it.address is Inet4Address && it.address.isSiteLocalAddress && it.prefixLength in 1..30}
        check(links.size==1){"ipv4_required"};val link=links.single();val ip=link.address.address
        val value=ip.fold(0){acc,b->(acc shl 8) or (b.toInt() and 255)}
        val mask=(-1 shl (32-link.prefixLength));val broadcast=value or mask.inv()
        val dest=InetAddress.getByAddress(byteArrayOf((broadcast ushr 24).toByte(),(broadcast ushr 16).toByte(),(broadcast ushr 8).toByte(),broadcast.toByte()))
        val sock=socket?:DatagramSocket().also{it.broadcast=true;network.bindSocket(it);socket=it}
        sock.send(DatagramPacket(packet,packet.size,dest,9))
    }
    override fun close(){socket?.close();socket=null}
}
