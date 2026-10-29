package com.qusadprod.sing_box.service

import android.content.Context
import android.util.Log
import com.qusadprod.sing_box.core.LibboxRuntime
import com.qusadprod.sing_box.core.SingBoxError
import com.qusadprod.sing_box.core.libboxMessage
import io.nekohasekai.libbox.CommandServer
import io.nekohasekai.libbox.CommandServerHandler
import io.nekohasekai.libbox.Libbox
import io.nekohasekai.libbox.OverrideOptions
import io.nekohasekai.libbox.SystemProxyStatus

/**
 * The probe core: a second libbox service in the app process that runs a config
 * without TUN (`direct` inbounds on 127.0.0.1) for latency tests while the VPN
 * is stopped. Its `CommandServer` is never started, so it opens no command
 * socket next to the VPN's. Blocking: call off the main thread.
 */
internal object ProbeCore {
    private const val TAG = "sing_box"
    private val lock = Any()
    private var server: CommandServer? = null

    /** Starts [config], replacing a running probe core. */
    fun start(context: Context, config: String) {
        synchronized(lock) {
            stopLocked()
            LibboxRuntime.ensureSetup(context)
            try {
                Libbox.checkConfig(config)
            } catch (e: Exception) {
                throw SingBoxError(SingBoxError.INVALID_CONFIG, e.libboxMessage)
            }
            // The local DNS transport and the interface monitor need the network monitor.
            DefaultNetworkMonitor.start(context, DefaultNetworkMonitor.OWNER_PROBE)
            val created = Libbox.newCommandServer(Handler, PlatformInterfaceImpl(context, null))
            try {
                created.startOrReloadService(config, OverrideOptions())
            } catch (e: Exception) {
                runCatching { created.closeService() }
                runCatching { created.close() }
                DefaultNetworkMonitor.stop(DefaultNetworkMonitor.OWNER_PROBE)
                throw SingBoxError(SingBoxError.START_FAILED, e.libboxMessage)
            }
            server = created
        }
    }

    /** Stops the probe core; no-op without one. */
    fun stop() {
        synchronized(lock) { stopLocked() }
    }

    private fun stopLocked() {
        val current = server ?: return
        server = null
        runCatching { current.closeService() }.onFailure { Log.w(TAG, "close probe core", it) }
        runCatching { current.close() }
        DefaultNetworkMonitor.stop(DefaultNetworkMonitor.OWNER_PROBE)
    }

    /** The probe core has no UI or system proxy: its service commands do nothing. */
    private object Handler : CommandServerHandler {
        override fun serviceStop() {}

        override fun serviceReload() {}

        override fun getSystemProxyStatus(): SystemProxyStatus = SystemProxyStatus()

        override fun setSystemProxyEnabled(isEnabled: Boolean) {}

        override fun triggerNativeCrash() {}

        override fun writeDebugMessage(message: String?) {
            Log.d(TAG, "probe core: $message")
        }

        override fun connectSSHAgent(): Int = -1
    }
}
