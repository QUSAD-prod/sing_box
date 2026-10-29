package com.qusadprod.sing_box.core

import android.content.Context
import android.content.SharedPreferences
import java.io.File

/** Android options of `initialize` (contract: `android` map). */
internal data class NotificationOptions(
    val channelId: String = DEFAULT_CHANNEL_ID,
    val channelName: String = DEFAULT_CHANNEL_NAME,
    val title: String? = null,
    val content: String = DEFAULT_CONTENT,
    val icon: String? = null,
    val showTraffic: Boolean = true,
    val showStopAction: Boolean = true,
    val stopActionTitle: String = DEFAULT_STOP_TITLE,
    val sessionName: String? = null,
) {
    companion object {
        const val DEFAULT_CHANNEL_ID = "sing_box_vpn"
        const val DEFAULT_CHANNEL_NAME = "VPN"
        const val DEFAULT_CONTENT = "Connected"
        const val DEFAULT_STOP_TITLE = "Stop"

        /** Parses the `android` map; unknown keys and wrongly typed values are ignored. */
        fun fromMap(map: Map<*, *>?): NotificationOptions {
            if (map == null) return NotificationOptions()
            fun string(key: String): String? = (map[key] as? String)?.takeIf { it.isNotBlank() }
            fun bool(key: String, default: Boolean): Boolean = map[key] as? Boolean ?: default
            return NotificationOptions(
                channelId = string("notificationChannelId") ?: DEFAULT_CHANNEL_ID,
                channelName = string("notificationChannelName") ?: DEFAULT_CHANNEL_NAME,
                title = string("notificationTitle"),
                content = string("notificationContent") ?: DEFAULT_CONTENT,
                icon = string("notificationIcon"),
                showTraffic = bool("showTrafficInNotification", true),
                showStopAction = bool("showStopAction", true),
                stopActionTitle = string("stopActionTitle") ?: DEFAULT_STOP_TITLE,
                sessionName = string("sessionName"),
            )
        }
    }
}

/**
 * Persistent service settings (`SharedPreferences("sing_box_service")`). They
 * are persisted so that a service started without the Flutter engine (boot,
 * always-on VPN, Quick Settings tile) behaves like one started by the app.
 */
internal class ServiceSettings(context: Context) {
    private val prefs: SharedPreferences =
        context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    var logMaxLines: Int
        get() = prefs.getInt(KEY_LOG_MAX_LINES, DEFAULT_LOG_MAX_LINES)
        set(value) = prefs.edit().putInt(KEY_LOG_MAX_LINES, value).apply()

    var debug: Boolean
        get() = prefs.getBoolean(KEY_DEBUG, false)
        set(value) = prefs.edit().putBoolean(KEY_DEBUG, value).apply()

    var startOnBoot: Boolean
        get() = prefs.getBoolean(KEY_START_ON_BOOT, false)
        set(value) = prefs.edit().putBoolean(KEY_START_ON_BOOT, value).apply()

    var quickSettingsTile: Boolean
        get() = prefs.getBoolean(KEY_QS_TILE, false)
        set(value) = prefs.edit().putBoolean(KEY_QS_TILE, value).apply()

    var tileLabel: String?
        get() = prefs.getString(KEY_TILE_LABEL, null)
        set(value) = prefs.edit().putString(KEY_TILE_LABEL, value).apply()

    /** True while the user wants the VPN to run (set on start, cleared on user stop). */
    var wasRunning: Boolean
        get() = prefs.getBoolean(KEY_WAS_RUNNING, false)
        set(value) {
            // commit(): must survive the process being killed right after a start/stop.
            prefs.edit().putBoolean(KEY_WAS_RUNNING, value).commit()
        }

    /** Memory monitor mode of `start` (`platformDefault`, `off`, `reportOnly`, `enabled`). */
    var oomKiller: String
        get() = prefs.getString(KEY_OOM_KILLER, null) ?: OOM_KILLER_PLATFORM_DEFAULT
        set(value) = prefs.edit().putString(KEY_OOM_KILLER, value).apply()

    /** Memory limit of the core in bytes, 0 = default. */
    var memoryLimit: Long
        get() = prefs.getLong(KEY_MEMORY_LIMIT, 0L)
        set(value) = prefs.edit().putLong(KEY_MEMORY_LIMIT, value).apply()

    var notificationOptions: NotificationOptions
        get() = NotificationOptions(
            channelId = prefs.getString(KEY_N_CHANNEL_ID, null) ?: NotificationOptions.DEFAULT_CHANNEL_ID,
            channelName = prefs.getString(KEY_N_CHANNEL_NAME, null) ?: NotificationOptions.DEFAULT_CHANNEL_NAME,
            title = prefs.getString(KEY_N_TITLE, null),
            content = prefs.getString(KEY_N_CONTENT, null) ?: NotificationOptions.DEFAULT_CONTENT,
            icon = prefs.getString(KEY_N_ICON, null),
            showTraffic = prefs.getBoolean(KEY_N_SHOW_TRAFFIC, true),
            showStopAction = prefs.getBoolean(KEY_N_SHOW_STOP, true),
            stopActionTitle = prefs.getString(KEY_N_STOP_TITLE, null) ?: NotificationOptions.DEFAULT_STOP_TITLE,
            sessionName = prefs.getString(KEY_N_SESSION, null),
        )
        set(value) {
            prefs.edit()
                .putString(KEY_N_CHANNEL_ID, value.channelId)
                .putString(KEY_N_CHANNEL_NAME, value.channelName)
                .putString(KEY_N_TITLE, value.title)
                .putString(KEY_N_CONTENT, value.content)
                .putString(KEY_N_ICON, value.icon)
                .putBoolean(KEY_N_SHOW_TRAFFIC, value.showTraffic)
                .putBoolean(KEY_N_SHOW_STOP, value.showStopAction)
                .putString(KEY_N_STOP_TITLE, value.stopActionTitle)
                .putString(KEY_N_SESSION, value.sessionName)
                .apply()
        }

    companion object {
        const val PREFS_NAME = "sing_box_service"
        const val DEFAULT_LOG_MAX_LINES = 3000
        const val OOM_KILLER_PLATFORM_DEFAULT = "platformDefault"
        const val OOM_KILLER_OFF = "off"
        const val OOM_KILLER_REPORT_ONLY = "reportOnly"
        const val OOM_KILLER_ENABLED = "enabled"

        private const val KEY_LOG_MAX_LINES = "logMaxLines"
        private const val KEY_DEBUG = "debug"
        private const val KEY_START_ON_BOOT = "startOnBoot"
        private const val KEY_QS_TILE = "quickSettingsTile"
        private const val KEY_TILE_LABEL = "tileLabel"
        private const val KEY_WAS_RUNNING = "wasRunning"
        private const val KEY_OOM_KILLER = "oomKiller"
        private const val KEY_MEMORY_LIMIT = "memoryLimit"
        private const val KEY_N_CHANNEL_ID = "notification.channelId"
        private const val KEY_N_CHANNEL_NAME = "notification.channelName"
        private const val KEY_N_TITLE = "notification.title"
        private const val KEY_N_CONTENT = "notification.content"
        private const val KEY_N_ICON = "notification.icon"
        private const val KEY_N_SHOW_TRAFFIC = "notification.showTraffic"
        private const val KEY_N_SHOW_STOP = "notification.showStopAction"
        private const val KEY_N_STOP_TITLE = "notification.stopActionTitle"
        private const val KEY_N_SESSION = "notification.sessionName"
    }
}

/** File locations of the contract table "Files and directories". */
internal object Paths {
    fun baseDir(context: Context): File = context.applicationContext.filesDir

    fun workingDir(context: Context): File = File(baseDir(context), "sing-box")

    fun tempDir(context: Context): File = context.applicationContext.cacheDir

    fun lastConfigFile(context: Context): File = File(workingDir(context), "last_config.json")

    fun readLastConfig(context: Context): String? {
        val file = lastConfigFile(context)
        return if (file.isFile) file.readText().takeIf { it.isNotBlank() } else null
    }

    fun writeLastConfig(context: Context, config: String) {
        val file = lastConfigFile(context)
        file.parentFile?.mkdirs()
        val tmp = File(file.parentFile, "${file.name}.tmp")
        tmp.writeText(config)
        if (!tmp.renameTo(file)) {
            file.writeText(config)
            tmp.delete()
        }
    }
}

/** Plain key/value storage of the contract (`SharedPreferences("sing_box")`). */
internal class KeyValueStorage(context: Context) {
    private val prefs = context.applicationContext.getSharedPreferences("sing_box", Context.MODE_PRIVATE)

    fun read(key: String): String? = prefs.getString(key, null)

    fun write(key: String, value: String?) {
        val editor = prefs.edit()
        if (value == null) editor.remove(key) else editor.putString(key, value)
        editor.apply()
    }
}
