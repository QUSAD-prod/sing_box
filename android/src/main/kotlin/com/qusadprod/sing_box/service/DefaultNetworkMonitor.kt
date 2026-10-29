/*
 * Adapted from sing-box-for-android (SFA) bg/DefaultNetworkListener.kt and
 * bg/DefaultNetworkMonitor.kt, originally based on shadowsocks-android:
 *   Copyright (C) 2019 by Max Lv <max.c.lv@gmail.com>
 *   Copyright (C) 2019 by Mygod Studio <contact-shadowsocks-android@mygod.be>
 * Licensed under the GNU General Public License v3.0 or later.
 */
package com.qusadprod.sing_box.service

import android.content.Context
import android.net.ConnectivityManager
import android.net.LinkProperties
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.util.Log
import io.nekohasekai.libbox.InterfaceUpdateListener
import java.net.NetworkInterface
import java.util.concurrent.CopyOnWriteArraySet

/**
 * Tracks the underlying (non-VPN) default network and reports it to libbox
 * (`auto_detect_interface`, local DNS transport, interface monitor).
 */
internal object DefaultNetworkMonitor {
    private const val TAG = "sing_box"

    @Volatile
    var defaultNetwork: Network? = null
        private set

    /** Owner of the VPN service ([start] / [stop]). */
    const val OWNER_VPN = "vpn"

    /** Owner of the probe core for latency tests. */
    const val OWNER_PROBE = "probe"

    private val listeners = CopyOnWriteArraySet<InterfaceUpdateListener>()
    private val owners = mutableSetOf<String>()
    private val lock = Any()
    private var connectivity: ConnectivityManager? = null
    private var registered = false

    private val callbackHandler: Handler by lazy {
        Handler(HandlerThread("sing-box-network").apply { start() }.looper)
    }

    // NetworkRequest.Builder() includes NOT_VPN by default, so our own tunnel is never reported.
    private val request: NetworkRequest by lazy {
        NetworkRequest.Builder()
            .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .addCapability(NetworkCapabilities.NET_CAPABILITY_NOT_RESTRICTED)
            .build()
    }

    /** Starts tracking on behalf of [owner] (the VPN service or the probe core). */
    fun start(context: Context, owner: String) {
        synchronized(lock) {
            owners += owner
            val manager = context.applicationContext.getSystemService(ConnectivityManager::class.java)
            connectivity = manager
            if (!registered) {
                register(manager)
                registered = true
            }
            if (defaultNetwork == null) defaultNetwork = manager.activeNetwork
        }
    }

    /** Stops tracking for [owner]; the callback is released once no owner is left. */
    fun stop(owner: String) {
        synchronized(lock) {
            owners -= owner
            if (owners.isNotEmpty()) return
            if (registered) {
                runCatching { connectivity?.unregisterNetworkCallback(callback) }
                registered = false
            }
            defaultNetwork = null
        }
    }

    fun addListener(listener: InterfaceUpdateListener) {
        listeners += listener
        // Report the current interface before returning (like SFA): the core dials right
        // after starting the monitor (initial rule-set downloads, DNS bootstrap) and fails
        // with "no available network interface" until it knows the default interface.
        // Called on a Go thread, never on the main thread.
        checkDefaultInterfaceUpdate(defaultNetwork, listOf(listener))
    }

    fun removeListener(listener: InterfaceUpdateListener) {
        listeners -= listener
    }

    private fun register(manager: ConnectivityManager) {
        // registerDefaultNetworkCallback returns the VPN itself since Android P, so request
        // THE best matching non-VPN network instead (needs CHANGE_NETWORK_STATE below 31).
        try {
            when {
                Build.VERSION.SDK_INT >= 31 -> manager.registerBestMatchingNetworkCallback(request, callback, callbackHandler)
                Build.VERSION.SDK_INT >= 28 -> manager.requestNetwork(request, callback, callbackHandler)
                Build.VERSION.SDK_INT >= 26 -> manager.registerDefaultNetworkCallback(callback, callbackHandler)
                else -> manager.registerDefaultNetworkCallback(callback)
            }
        } catch (e: RuntimeException) {
            // Known OEM bugs; libbox then works with the initial activeNetwork only.
            Log.w(TAG, "register network callback", e)
        }
    }

    private val callback = object : ConnectivityManager.NetworkCallback() {
        override fun onAvailable(network: Network) {
            defaultNetwork = network
            setUnderlyingNetwork(network)
            checkDefaultInterfaceUpdate(network)
        }

        override fun onCapabilitiesChanged(network: Network, networkCapabilities: NetworkCapabilities) {
            if (network == defaultNetwork) checkDefaultInterfaceUpdate(network)
        }

        override fun onLinkPropertiesChanged(network: Network, linkProperties: LinkProperties) {
            if (network == defaultNetwork) checkDefaultInterfaceUpdate(network)
        }

        override fun onLost(network: Network) {
            if (network == defaultNetwork) {
                defaultNetwork = null
                setUnderlyingNetwork(null)
                checkDefaultInterfaceUpdate(null)
            }
        }
    }

    /**
     * Tells the system which network carries the tunnel, so the VPN inherits its
     * capabilities (metered, transport); `null` falls back to the system default.
     */
    private fun setUnderlyingNetwork(network: Network?) {
        val service = SingBoxVpnService.vpnInstance ?: return
        runCatching { service.setUnderlyingNetworks(network?.let { arrayOf(it) }) }
            .onFailure { Log.w(TAG, "set underlying networks", it) }
    }

    /** Runs on the callback thread: probes the interface with retries (never on the main thread). */
    private fun checkDefaultInterfaceUpdate(
        network: Network?,
        targets: Collection<InterfaceUpdateListener> = listeners,
    ) {
        if (targets.isEmpty()) return
        val manager = connectivity ?: return
        if (network == null) {
            for (current in targets) runCatching { current.updateDefaultInterface("", -1, false, false) }
            return
        }
        repeat(10) {
            val linkProperties = manager.getLinkProperties(network)
            val name = linkProperties?.interfaceName
            if (name != null) {
                val index = runCatching { NetworkInterface.getByName(name)?.index }.getOrNull()
                if (index != null) {
                    val capabilities = manager.getNetworkCapabilities(network)
                    val expensive = capabilities?.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED) == false
                    for (current in targets) {
                        runCatching { current.updateDefaultInterface(name, index, expensive, false) }
                            .onFailure { Log.w(TAG, "update default interface", it) }
                    }
                    return
                }
            }
            Thread.sleep(100)
        }
    }
}
