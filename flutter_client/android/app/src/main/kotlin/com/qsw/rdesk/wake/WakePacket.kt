package com.qsw.rdesk.wake

object WakePacket {
    fun encode(mac:String):ByteArray {
        require(Regex("^[0-9A-Fa-f]{2}([:-][0-9A-Fa-f]{2}){5}$").matches(mac))
        val bytes=mac.replace('-',':').split(':').map{it.toInt(16).toByte()}.toByteArray()
        require(bytes.any{it.toInt()!=0} && (bytes[0].toInt() and 1)==0)
        return ByteArray(102){index->if(index<6)0xff.toByte() else bytes[(index-6)%6]}
    }
}
