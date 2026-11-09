package com.yutan123.tidebot

import android.database.sqlite.SQLiteDatabase
import org.json.JSONObject

/** Shared with Dart's ProactiveRequestGate; read inside the publishing transaction. */
object TideProactiveRequestGate {
    fun generation(db: SQLiteDatabase, botId: String): String = state(db, botId).optString("generation")

    private fun state(db: SQLiteDatabase, botId: String): JSONObject =
        runCatching { JSONObject(TideStore.kv(db, "chat_proactive_gate_$botId") ?: "{}") }
            .getOrDefault(JSONObject())

    fun busy(db: SQLiteDatabase, botId: String): Boolean {
        val state = state(db, botId)
        val now = System.currentTimeMillis()
        if (state.optLong("pendingUntil") > now) return true
        val chats = state.optJSONObject("chats") ?: return false
        return chats.keys().asSequence().any { chats.optLong(it) > now }
    }

    fun allowed(db: SQLiteDatabase, botId: String, expectedGeneration: String, due: String?): Boolean =
        !busy(db, botId) && generation(db, botId) == expectedGeneration &&
            TideStore.kv(db, "proactive_due_at_$botId") == due
}
