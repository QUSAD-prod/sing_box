package com.qusadprod.sing_box

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import com.google.gson.Gson
import com.google.gson.JsonSyntaxException

/**
 * Manager for managing server configurations
 * Uses SQLite for storing configurations
 */
class ServerConfigManager(private val context: Context) {
    private val gson = Gson()
    private val dbHelper = ServerConfigDbHelper(context)
    
    /**
     * Add server configuration
     */
    fun addServerConfig(config: Map<String, Any?>): Boolean {
        return try {
            val configId = config["id"] as? String
            if (configId.isNullOrBlank()) {
                return false
            }
            
            dbHelper.writableDatabase.use { db ->
                val values = ContentValues().apply {
                    put(ServerConfigDbHelper.COLUMN_CONFIG_ID, configId)
                    put(ServerConfigDbHelper.COLUMN_NAME, config["name"] as? String ?: "")
                    put(ServerConfigDbHelper.COLUMN_CONFIG_JSON, gson.toJson(config))
                    put(ServerConfigDbHelper.COLUMN_CREATED_AT, System.currentTimeMillis())
                    put(ServerConfigDbHelper.COLUMN_UPDATED_AT, System.currentTimeMillis())
                }
                
                val result = db.insertWithOnConflict(
                    ServerConfigDbHelper.TABLE_SERVER_CONFIGS,
                    null,
                    values,
                    SQLiteDatabase.CONFLICT_REPLACE
                )
                result != -1L
            }
        } catch (e: Exception) {
            false
        }
    }
    
    /**
     * Remove server configuration
     */
    fun removeServerConfig(configId: String): Boolean {
        return try {
            dbHelper.writableDatabase.use { db ->
                val result = db.delete(
                    ServerConfigDbHelper.TABLE_SERVER_CONFIGS,
                    "${ServerConfigDbHelper.COLUMN_CONFIG_ID} = ?",
                    arrayOf(configId)
                )
                result > 0
            }
        } catch (e: Exception) {
            false
        }
    }
    
    /**
     * Update server configuration
     */
    fun updateServerConfig(config: Map<String, Any?>): Boolean {
        return try {
            val configId = config["id"] as? String
            if (configId.isNullOrBlank()) {
                return false
            }
            
            dbHelper.writableDatabase.use { db ->
                val values = ContentValues().apply {
                    put(ServerConfigDbHelper.COLUMN_NAME, config["name"] as? String ?: "")
                    put(ServerConfigDbHelper.COLUMN_CONFIG_JSON, gson.toJson(config))
                    put(ServerConfigDbHelper.COLUMN_UPDATED_AT, System.currentTimeMillis())
                }
                
                val result = db.update(
                    ServerConfigDbHelper.TABLE_SERVER_CONFIGS,
                    values,
                    "${ServerConfigDbHelper.COLUMN_CONFIG_ID} = ?",
                    arrayOf(configId)
                )
                result > 0
            }
        } catch (e: Exception) {
            false
        }
    }
    
    /**
     * Get all server configurations
     */
    fun getServerConfigs(): List<Map<String, Any?>> {
        val configs = mutableListOf<Map<String, Any?>>()
        return try {
            dbHelper.readableDatabase.use { db ->
                db.query(
                    ServerConfigDbHelper.TABLE_SERVER_CONFIGS,
                    arrayOf(
                        ServerConfigDbHelper.COLUMN_CONFIG_JSON
                    ),
                    null,
                    null,
                    null,
                    null,
                    "${ServerConfigDbHelper.COLUMN_CREATED_AT} DESC"
                ).use { cursor ->
                    while (cursor.moveToNext()) {
                        val configJson = cursor.getString(0)
                        try {
                            val configType = object : com.google.gson.reflect.TypeToken<Map<String, Any?>>() {}.type
                            val config: Map<String, Any?> = gson.fromJson(configJson, configType) ?: continue
                            configs.add(config)
                        } catch (e: JsonSyntaxException) {
                            // Skip invalid configurations
                            continue
                        }
                    }
                }
            }
            configs
        } catch (e: Exception) {
            emptyList()
        }
    }
    
    /**
     * Get server configuration by ID
     */
    fun getServerConfig(configId: String): Map<String, Any?>? {
        return try {
            dbHelper.readableDatabase.use { db ->
                db.query(
                    ServerConfigDbHelper.TABLE_SERVER_CONFIGS,
                    arrayOf(ServerConfigDbHelper.COLUMN_CONFIG_JSON),
                    "${ServerConfigDbHelper.COLUMN_CONFIG_ID} = ?",
                    arrayOf(configId),
                    null,
                    null,
                    null
                ).use { cursor ->
                    if (cursor.moveToFirst()) {
                        val configJson = cursor.getString(0)
                        val configType = object : com.google.gson.reflect.TypeToken<Map<String, Any?>>() {}.type
                        gson.fromJson(configJson, configType)
                    } else {
                        null
                    }
                }
            }
        } catch (e: Exception) {
            null
        }
    }
    
    /**
     * Set active server configuration
     */
    fun setActiveServerConfig(configId: String?): Boolean {
        return try {
            // Save active configuration to SettingsManager
            val settingsManager = SettingsManager(context)
            settingsManager.updateSetting("activeServerConfigId", configId)
            true
        } catch (e: Exception) {
            false
        }
    }
    
    /**
     * Get active server configuration
     */
    fun getActiveServerConfig(): Map<String, Any?>? {
        return try {
            val settingsManager = SettingsManager(context)
            val settings = settingsManager.getSettings()
            val activeConfigId = settings["activeServerConfigId"] as? String
            
            if (activeConfigId.isNullOrBlank()) {
                return null
            }
            
            getServerConfig(activeConfigId)
        } catch (e: Exception) {
            null
        }
    }
    
    /**
     * Get active server configuration ID
     */
    fun getActiveServerConfigId(): String? {
        return try {
            val settingsManager = SettingsManager(context)
            val settings = settingsManager.getSettings()
            settings["activeServerConfigId"] as? String
        } catch (e: Exception) {
            null
        }
    }
    
    /**
     * SQLite Helper for server configurations
     */
    private class ServerConfigDbHelper(context: Context) : SQLiteOpenHelper(
        context,
        DATABASE_NAME,
        null,
        DATABASE_VERSION
    ) {
        companion object {
            const val DATABASE_NAME = "sing_box_server_configs.db"
            const val DATABASE_VERSION = 1
            const val TABLE_SERVER_CONFIGS = "server_configs"
            const val COLUMN_ID = "_id"
            const val COLUMN_CONFIG_ID = "config_id"
            const val COLUMN_NAME = "name"
            const val COLUMN_CONFIG_JSON = "config_json"
            const val COLUMN_CREATED_AT = "created_at"
            const val COLUMN_UPDATED_AT = "updated_at"
        }
        
        override fun onCreate(db: SQLiteDatabase) {
            val createTable = """
                CREATE TABLE $TABLE_SERVER_CONFIGS (
                    $COLUMN_ID INTEGER PRIMARY KEY AUTOINCREMENT,
                    $COLUMN_CONFIG_ID TEXT UNIQUE NOT NULL,
                    $COLUMN_NAME TEXT NOT NULL,
                    $COLUMN_CONFIG_JSON TEXT NOT NULL,
                    $COLUMN_CREATED_AT INTEGER NOT NULL,
                    $COLUMN_UPDATED_AT INTEGER NOT NULL
                )
            """.trimIndent()
            db.execSQL(createTable)
        }
        
        override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
            db.execSQL("DROP TABLE IF EXISTS $TABLE_SERVER_CONFIGS")
            onCreate(db)
        }
    }
}

