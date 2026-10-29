package com.qusadprod.sing_box.core

import android.content.Context
import android.content.pm.ApplicationInfo
import android.os.Build
import android.util.Log
import io.nekohasekai.libbox.Libbox
import io.nekohasekai.libbox.SetupOptions
import org.json.JSONObject
import java.util.Locale

/** Guards the single `Libbox.setup` call of the process. */
internal object LibboxRuntime {
    private const val TAG = "sing_box"
    private val lock = Any()

    @Volatile
    var isSetup: Boolean = false
        private set

    /**
     * Loads the native library and runs `Libbox.setup` once per process. Blocking
     * (the first call loads a ~60 MB shared library): call it off the main thread.
     * Uses the options persisted by `initialize`, so a service started at boot
     * (without the Flutter engine) is set up the same way.
     */
    fun ensureSetup(context: Context) {
        if (isSetup) return
        synchronized(lock) {
            if (isSetup) return
            val app = context.applicationContext
            val settings = ServiceSettings(app)
            Paths.baseDir(app).mkdirs()
            val working = Paths.workingDir(app).apply { mkdirs() }
            Paths.tempDir(app).mkdirs()
            runCatching { Libbox.setLocale(Locale.getDefault().toLanguageTag()) }
                .onFailure { Log.d(TAG, "set locale: ${it.message}") }
            Libbox.setup(setupOptions(app, settings))
            isSetup = true
            Log.i(TAG, "libbox ${Libbox.version()} set up in ${working.path}")
        }
    }

    /**
     * Applies the stored memory monitor options (`ServiceSettings.oomKiller` /
     * `memoryLimit`) to libbox. A command server reads them when it is created,
     * so call this before `Libbox.newCommandServer`. Requires [ensureSetup].
     */
    fun reloadOptions(context: Context) {
        synchronized(lock) {
            if (!isSetup) return
            val app = context.applicationContext
            Libbox.reloadSetupOptions(setupOptions(app, ServiceSettings(app)))
        }
    }

    private fun setupOptions(app: Context, settings: ServiceSettings) = SetupOptions().apply {
        basePath = Paths.baseDir(app).path
        workingPath = Paths.workingDir(app).path
        tempPath = Paths.tempDir(app).path
        fixAndroidStack = fixAndroidStack(app)
        logMaxLines = settings.logMaxLines.toLong()
        debug = settings.debug
        crashReportSource = "sing_box"
        appVersion = appVersionCode(app)
        appMarketingVersion = appVersionName(app)
        // libbox has no fixed memory limit on Android (that is an iOS network
        // extension constraint): the OOM killer is off by default, like SFA.
        when (settings.oomKiller) {
            ServiceSettings.OOM_KILLER_ENABLED -> {
                oomKillerEnabled = true
                oomKillerDisabled = false
            }
            ServiceSettings.OOM_KILLER_REPORT_ONLY -> {
                oomKillerEnabled = true
                oomKillerDisabled = true
            }
            else -> {
                oomKillerEnabled = false
                oomKillerDisabled = true
            }
        }
        // 0: the killer watches the available system memory instead of a limit.
        oomMemoryLimit = settings.memoryLimit.coerceAtLeast(0L)
        powerReportEnabled = false
        // Part of crash and OOM reports.
        platformMetadata = JSONObject().apply {
            put("os", "Android " + Build.VERSION.RELEASE)
            put("sdk", Build.VERSION.SDK_INT)
            put("manufacturer", Build.MANUFACTURER)
            put("model", Build.MODEL)
        }.toString()
    }

    // TODO: remove once https://github.com/golang/go/issues/68760 is fixed (same as SFA).
    private fun fixAndroidStack(context: Context): Boolean {
        val debuggable = context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0
        return debuggable ||
            Build.VERSION.SDK_INT in Build.VERSION_CODES.N..Build.VERSION_CODES.N_MR1 ||
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.P
    }

    @Suppress("DEPRECATION")
    private fun appVersionCode(context: Context): String = runCatching {
        val info = context.packageManager.getPackageInfo(context.packageName, 0)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) info.longVersionCode.toString() else info.versionCode.toString()
    }.getOrDefault("0")

    private fun appVersionName(context: Context): String = runCatching {
        context.packageManager.getPackageInfo(context.packageName, 0).versionName ?: ""
    }.getOrDefault("")
}
