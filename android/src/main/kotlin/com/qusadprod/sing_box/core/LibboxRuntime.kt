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
            val base = Paths.baseDir(app).apply { mkdirs() }
            val working = Paths.workingDir(app).apply { mkdirs() }
            val temp = Paths.tempDir(app).apply { mkdirs() }
            runCatching { Libbox.setLocale(Locale.getDefault().toLanguageTag()) }
                .onFailure { Log.d(TAG, "set locale: ${it.message}") }
            val options = SetupOptions().apply {
                basePath = base.path
                workingPath = working.path
                tempPath = temp.path
                fixAndroidStack = fixAndroidStack(app)
                logMaxLines = settings.logMaxLines.toLong()
                debug = settings.debug
                crashReportSource = "sing_box"
                appVersion = appVersionCode(app)
                appMarketingVersion = appVersionName(app)
                // libbox 1.14 has no fixed memory limit on Android (that is an
                // iOS network extension constraint); keep the OOM killer off like SFA.
                oomKillerEnabled = false
                oomKillerDisabled = true
                oomMemoryLimit = 0
                powerReportEnabled = false
                // Part of crash and OOM reports.
                platformMetadata = JSONObject().apply {
                    put("os", "Android " + Build.VERSION.RELEASE)
                    put("sdk", Build.VERSION.SDK_INT)
                    put("manufacturer", Build.MANUFACTURER)
                    put("model", Build.MODEL)
                }.toString()
            }
            Libbox.setup(options)
            isSetup = true
            Log.i(TAG, "libbox ${Libbox.version()} set up in ${working.path}")
        }
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
