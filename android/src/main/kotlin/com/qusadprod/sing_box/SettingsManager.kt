package com.qusadprod.sing_box

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import com.google.gson.Gson
import com.google.gson.reflect.TypeToken

/**
 * Manager for managing plugin settings
 * Uses SQLite for storing settings
 */
class SettingsManager(private val context: Context) {
    private val gson = Gson()
    private val dbHelper = SettingsDatabaseHelper(context)
    
    // Cache for current settings
    private var cachedSettings: Map<String, Any?>? = null
    
    /**
     * Save settings
     */
    fun saveSettings(settings: Map<String, Any?>): Boolean {
        return try {
            dbHelper.writableDatabase.use { db ->
                val settingsJson = gson.toJson(settings)
                
                val values = android.content.ContentValues().apply {
                    put(SettingsDatabaseHelper.COLUMN_KEY, "settings")
                    put(SettingsDatabaseHelper.COLUMN_VALUE, settingsJson)
                    put(SettingsDatabaseHelper.COLUMN_UPDATED_AT, System.currentTimeMillis())
                }
                
                val result = db.insertWithOnConflict(
                    SettingsDatabaseHelper.TABLE_SETTINGS,
                    null,
                    values,
                    SQLiteDatabase.CONFLICT_REPLACE
                )
                
                cachedSettings = settings
                result != -1L
            }
        } catch (e: Exception) {
            false
        }
    }
    
    /**
     * Load settings
     */
    fun loadSettings(): Map<String, Any?> {
        // Check cache
        if (cachedSettings != null) {
            return cachedSettings ?: getDefaultSettings()
        }
        
        return try {
            dbHelper.readableDatabase.use { db ->
                db.query(
                    SettingsDatabaseHelper.TABLE_SETTINGS,
                    arrayOf(SettingsDatabaseHelper.COLUMN_VALUE),
                    "${SettingsDatabaseHelper.COLUMN_KEY} = ?",
                    arrayOf("settings"),
                    null,
                    null,
                    null
                ).use { cursor ->
                    if (cursor.moveToFirst()) {
                        val settingsJson = cursor.getString(0)
                        val settingsType = object : TypeToken<Map<String, Any?>>() {}.type
                        val settings: Map<String, Any?> = gson.fromJson(settingsJson, settingsType) ?: getDefaultSettings()
                        cachedSettings = settings
                        settings
                    } else {
                        val defaultSettings = getDefaultSettings()
                        cachedSettings = defaultSettings
                        defaultSettings
                    }
                }
            }
        } catch (e: Exception) {
            getDefaultSettings()
        }
    }
    
    /**
     * Get current settings
     */
    fun getSettings(): Map<String, Any?> {
        return loadSettings()
    }
    
    /**
     * Update individual setting
     */
    fun updateSetting(key: String, value: Any?): Boolean {
        return try {
            val currentSettings = loadSettings().toMutableMap()
            currentSettings[key] = value
            saveSettings(currentSettings)
        } catch (e: Exception) {
            false
        }
    }
    
    /**
     * Get default settings
     */
    private fun getDefaultSettings(): Map<String, Any?> {
        return mapOf(
            "autoConnectOnStart" to false,
            "autoReconnectOnDisconnect" to false,
            "killSwitch" to false,
            "blockedApps" to emptyList<String>(),
            "blockedDomains" to emptyList<String>(),
            "bypassSubnets" to listOf(
                "192.168.0.0/16",
                "10.0.0.0/8",
                "172.16.0.0/12",
                "127.0.0.0/8",
                "169.254.0.0/16"
            ),
            "dnsServers" to listOf("8.8.8.8", "1.1.1.1"),
            "activeServerConfigId" to null,
            "serverConfigs" to emptyList<Map<String, Any>>(),
            "systemProxyEnabled" to false
        )
    }
    
    /**
     * Clear cache
     */
    fun clearCache() {
        cachedSettings = null
    }
    
    /**
     * SQLite Helper for settings
     */
    private class SettingsDatabaseHelper(context: Context) : SQLiteOpenHelper(
        context,
        DATABASE_NAME,
        null,
        DATABASE_VERSION
    ) {
        companion object {
            const val DATABASE_NAME = "sing_box_settings.db"
            const val DATABASE_VERSION = 1
            const val TABLE_SETTINGS = "settings"
            const val COLUMN_ID = "_id"
            const val COLUMN_KEY = "key"
            const val COLUMN_VALUE = "value"
            const val COLUMN_UPDATED_AT = "updated_at"
        }
        
        override fun onCreate(db: SQLiteDatabase) {
            val createTable = """
                CREATE TABLE $TABLE_SETTINGS (
                    $COLUMN_ID INTEGER PRIMARY KEY AUTOINCREMENT,
                    $COLUMN_KEY TEXT UNIQUE NOT NULL,
                    $COLUMN_VALUE TEXT NOT NULL,
                    $COLUMN_UPDATED_AT INTEGER NOT NULL
                )
            """.trimIndent()
            db.execSQL(createTable)
        }
        
        override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
            db.execSQL("DROP TABLE IF EXISTS $TABLE_SETTINGS")
            onCreate(db)
        }
    }
}

