package com.yutan123.tidebot

import android.content.Context
import android.database.Cursor
import android.database.sqlite.SQLiteDatabase
import org.json.JSONObject

/** Opens the existing sqflite database; never creates a second database or changes user_version. */
object TideStore {
    fun open(context: Context): SQLiteDatabase {
        val file = context.getDatabasePath("tidebot.db")
        check(file.exists()) { "Flutter database has not been initialized" }
        val db = SQLiteDatabase.openDatabase(file.path, null, SQLiteDatabase.OPEN_READWRITE)
        try {
            // busy_timeout returns a row even when assigning a value. Android rejects
            // row-returning statements in execSQL, so execute and close a query instead.
            db.rawQuery("PRAGMA busy_timeout=10000", null).use { cursor ->
                check(cursor.moveToFirst() && cursor.getInt(0) == 10000) {
                    "Failed to configure SQLite busy timeout"
                }
            }
            db.setForeignKeyConstraintsEnabled(true)
            return db
        } catch (error: Exception) {
            db.close()
            throw error
        }
    }
    fun rows(db: SQLiteDatabase, sql: String, vararg args: String): List<JSONObject> =
        db.rawQuery(sql, args).use { cursor ->
            buildList {
                while (cursor.moveToNext()) {
                    val row = JSONObject()
                    for (i in 0 until cursor.columnCount) {
                        row.put(cursor.getColumnName(i), when (cursor.getType(i)) {
                            Cursor.FIELD_TYPE_NULL -> JSONObject.NULL
                            Cursor.FIELD_TYPE_INTEGER -> cursor.getLong(i)
                            Cursor.FIELD_TYPE_FLOAT -> cursor.getDouble(i)
                            else -> cursor.getString(i)
                        })
                    }
                    add(row)
                }
            }
        }
    fun kv(db: SQLiteDatabase, key: String): String? =
        db.rawQuery("SELECT value FROM kv_store WHERE key=?", arrayOf(key)).use {
            if (it.moveToFirst() && !it.isNull(0)) it.getString(0) else null
        }
    fun put(db: SQLiteDatabase, key: String, value: String) {
        db.execSQL("INSERT OR REPLACE INTO kv_store(key,value) VALUES (?,?)", arrayOf(key, value))
    }
    inline fun <T> transaction(db: SQLiteDatabase, action: () -> T): T {
        db.beginTransaction()
        try {
            val result = action()
            db.setTransactionSuccessful()
            return result
        } finally { db.endTransaction() }
    }
}
