package com.qsw.rdesk.wake

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import org.json.JSONObject
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

data class WakeConfig(val endpoint:String,val agentId:String,val token:String,val ownerId:String)
class WakeRelayStore(context:Context):WakeJournal {
    private val prefs=context.getSharedPreferences("rdesk_wake_agent",Context.MODE_PRIVATE)
    private fun key():SecretKey {
        val store=KeyStore.getInstance("AndroidKeyStore");store.load(null)
        (store.getKey("rdesk-wake-agent",null) as? SecretKey)?.let{return it}
        val generator=KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES,"AndroidKeyStore")
        generator.init(KeyGenParameterSpec.Builder("rdesk-wake-agent",KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build())
        return generator.generateKey()
    }
    @Synchronized fun save(config:WakeConfig) {
        val cipher=Cipher.getInstance("AES/GCM/NoPadding");cipher.init(Cipher.ENCRYPT_MODE,key())
        val json=JSONObject().put("endpoint",config.endpoint).put("agentId",config.agentId).put("token",config.token).put("ownerId",config.ownerId)
        val encrypted=cipher.doFinal(json.toString().toByteArray(Charsets.UTF_8))
        check(prefs.edit().putString("cipher",Base64.encodeToString(encrypted,Base64.NO_WRAP)).putString("iv",Base64.encodeToString(cipher.iv,Base64.NO_WRAP)).commit())
    }
    @Synchronized fun load():WakeConfig? {
        val raw=prefs.getString("cipher",null)?:return null;val iv=prefs.getString("iv",null)?:return null
        val cipher=Cipher.getInstance("AES/GCM/NoPadding");cipher.init(Cipher.DECRYPT_MODE,key(),GCMParameterSpec(128,Base64.decode(iv,Base64.NO_WRAP)))
        val json=JSONObject(String(cipher.doFinal(Base64.decode(raw,Base64.NO_WRAP)),Charsets.UTF_8))
        return WakeConfig(json.getString("endpoint"),json.getString("agentId"),json.getString("token"),json.getString("ownerId"))
    }
    @Synchronized fun clear(){check(prefs.edit().remove("cipher").remove("iv").commit())}
    @Synchronized override fun reserve(id:String):Boolean {
        val rows=JSONObject(prefs.getString("journal","{}")!!);if(rows.has(id))return false
        rows.put(id,"uncertain");while(rows.length()>100)rows.remove(rows.keys().next())
        check(prefs.edit().putString("journal",rows.toString()).commit());return true
    }
    @Synchronized override fun finish(id:String,sent:Boolean) {
        val rows=JSONObject(prefs.getString("journal","{}")!!);rows.put(id,if(sent)"sent" else "failed")
        check(prefs.edit().putString("journal",rows.toString()).commit())
    }
    @Synchronized override fun outcome(id:String):Boolean? {
        val rows=JSONObject(prefs.getString("journal","{}")!!)
        return when(rows.optString(id)){"sent"->true;"failed"->false;else->null}
    }
}
