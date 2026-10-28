/*
 * Adapted from sing-box-for-android (SFA) bg/PlatformInterfaceWrapper.kt (GPL-3.0-or-later).
 */
package com.qusadprod.sing_box.service

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Process
import android.provider.Settings
import android.system.OsConstants
import android.util.Log
import com.qusadprod.sing_box.core.StringArray
import io.nekohasekai.libbox.BridgeOptions
import io.nekohasekai.libbox.BridgeSession
import io.nekohasekai.libbox.ConnectionOwner
import io.nekohasekai.libbox.InterfaceUpdateListener
import io.nekohasekai.libbox.Libbox
import io.nekohasekai.libbox.LocalDNSTransport
import io.nekohasekai.libbox.NeighborUpdateListener
import io.nekohasekai.libbox.NetworkInterfaceIterator
import io.nekohasekai.libbox.Notification
import io.nekohasekai.libbox.PlatformInterface
import io.nekohasekai.libbox.PlatformUser
import io.nekohasekai.libbox.ShellSession
import io.nekohasekai.libbox.StringIterator
import io.nekohasekai.libbox.TunOptions
import io.nekohasekai.libbox.WIFIState
import java.net.Inet6Address
import java.net.InetSocketAddress
import java.net.InterfaceAddress
import java.net.NetworkInterface
import io.nekohasekai.libbox.NetworkInterface as LibboxNetworkInterface

/**
 * libbox `PlatformInterface` for the VPN service. Features that need root or
 * are specific to other platforms (shell, SFTP, bridge, neighbor table) are
 * reported as unsupported.
 */
internal class PlatformInterfaceImpl(private val service: SingBoxVpnService) : PlatformInterface {
    private val context: Context = service.applicationContext
    private val connectivity: ConnectivityManager = context.getSystemService(ConnectivityManager::class.java)
    private val wifiManager: WifiManager? = context.getSystemService(WifiManager::class.java)

    override fun usePlatformAutoDetectInterfaceControl(): Boolean = true

    override fun autoDetectInterfaceControl(fd: Int) {
        if (!service.protect(fd)) {
            Log.w(TAG, "protect($fd) failed")
        }
    }

    override fun openTun(options: TunOptions): Int = service.openTun(options)

    override fun findConnectionOwner(
        ipProtocol: Int,
        sourceAddress: String,
        sourcePort: Int,
        destinationAddress: String,
        destinationPort: Int,
    ): ConnectionOwner {
        val owner = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val uid = connectivity.getConnectionOwnerUid(
                ipProtocol,
                InetSocketAddress(sourceAddress, sourcePort),
                InetSocketAddress(destinationAddress, destinationPort),
            )
            if (uid == Process.INVALID_UID) error("android: connection owner not found")
            ConnectionOwner().also { it.userId = uid }
        } else {
            Libbox.findConnectionOwner(ipProtocol, sourceAddress, sourcePort, destinationAddress, destinationPort)
        }
        val packages = context.packageManager.getPackagesForUid(owner.userId)?.toList().orEmpty()
        owner.userName = packages.firstOrNull() ?: ""
        owner.setAndroidPackageNames(StringArray(packages))
        return owner
    }

    override fun startDefaultInterfaceMonitor(listener: InterfaceUpdateListener) {
        DefaultNetworkMonitor.setListener(listener)
    }

    override fun closeDefaultInterfaceMonitor(listener: InterfaceUpdateListener) {
        DefaultNetworkMonitor.setListener(null)
    }

    @Suppress("DEPRECATION")
    override fun getInterfaces(): NetworkInterfaceIterator {
        val javaInterfaces = runCatching { NetworkInterface.getNetworkInterfaces()?.toList() }.getOrNull().orEmpty()
        val result = mutableListOf<LibboxNetworkInterface>()
        for (network in connectivity.allNetworks) {
            val linkProperties = connectivity.getLinkProperties(network) ?: continue
            val capabilities = connectivity.getNetworkCapabilities(network) ?: continue
            val name = linkProperties.interfaceName ?: continue
            val javaInterface = javaInterfaces.find { it.name == name } ?: continue
            val boxInterface = LibboxNetworkInterface()
            boxInterface.name = name
            boxInterface.index = javaInterface.index
            runCatching { boxInterface.mtu = javaInterface.mtu }
            boxInterface.dnsServer = StringArray(linkProperties.dnsServers.mapNotNull { it.hostAddress })
            boxInterface.gateway = StringArray(
                linkProperties.routes
                    .filter { it.destination.prefixLength == 0 }
                    .mapNotNull { it.gateway }
                    .filterNot { it.isAnyLocalAddress }
                    .mapNotNull { it.hostAddress },
            )
            boxInterface.type = when {
                capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> Libbox.InterfaceTypeWIFI
                capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> Libbox.InterfaceTypeCellular
                capabilities.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> Libbox.InterfaceTypeEthernet
                else -> Libbox.InterfaceTypeOther
            }
            boxInterface.addresses = StringArray(javaInterface.interfaceAddresses.map { it.toPrefix() })
            var flags = 0
            if (capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)) {
                flags = OsConstants.IFF_UP or OsConstants.IFF_RUNNING
            }
            if (javaInterface.isLoopback) flags = flags or OsConstants.IFF_LOOPBACK
            if (javaInterface.isPointToPoint) flags = flags or OsConstants.IFF_POINTOPOINT
            if (javaInterface.supportsMulticast()) flags = flags or OsConstants.IFF_MULTICAST
            boxInterface.flags = flags
            boxInterface.metered = !capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED)
            result.add(boxInterface)
        }
        val iterator = result.iterator()
        return object : NetworkInterfaceIterator {
            override fun hasNext(): Boolean = iterator.hasNext()

            override fun next(): LibboxNetworkInterface = iterator.next()
        }
    }

    override fun underNetworkExtension(): Boolean = false

    override fun includeAllNetworks(): Boolean = false

    override fun clearDNSCache() {}

    /**
     * Needs ACCESS_WIFI_STATE; the SSID/BSSID are only readable with location
     * permission (ACCESS_FINE_LOCATION, ACCESS_BACKGROUND_LOCATION on Q+), which
     * the plugin does not declare. Without it the SSID is empty.
     */
    @Suppress("DEPRECATION")
    override fun readWIFIState(): WIFIState? {
        val info = runCatching { wifiManager?.connectionInfo }.getOrNull() ?: return null
        var ssid = info.ssid ?: return WIFIState("", "")
        if (ssid == WifiManager.UNKNOWN_SSID) return WIFIState("", "")
        if (ssid.length >= 2 && ssid.startsWith("\"") && ssid.endsWith("\"")) {
            ssid = ssid.substring(1, ssid.length - 1)
        }
        return WIFIState(ssid, info.bssid ?: "")
    }

    override fun localDNSTransport(): LocalDNSTransport = LocalResolver

    override fun sendNotification(notification: Notification) {
        service.showCoreNotification(notification)
    }

    override fun cancelNotification(identifier: String, typeID: Int) {
        service.cancelCoreNotification(identifier, typeID)
    }

    override fun startNeighborMonitor(listener: NeighborUpdateListener?) {
        // Reading the neighbor table needs root on Android; not supported.
    }

    override fun closeNeighborMonitor(listener: NeighborUpdateListener?) {}

    override fun registerMyInterface(name: String?) {}

    override fun usePlatformShell(): Boolean = false

    override fun checkPlatformShell() {
        unsupported("platform shell")
    }

    override fun openShellSession(
        user: PlatformUser?,
        command: String?,
        environ: StringIterator?,
        term: String?,
        rows: Int,
        cols: Int,
    ): ShellSession = unsupported("shell sessions")

    override fun lookupUser(username: String?): PlatformUser = unsupported("user lookup")

    override fun lookupSFTPServer(): String = unsupported("SFTP server")

    override fun readSystemSSHHostKey(): String = unsupported("system SSH host key")

    override fun tailscaleHostname(): String =
        runCatching { Settings.Global.getString(context.contentResolver, Settings.Global.DEVICE_NAME) }
            .getOrNull()?.takeIf { it.isNotBlank() }
            ?: "${Build.MANUFACTURER} ${Build.MODEL}"

    override fun usePlatformBridge(): Boolean = false

    override fun createBridge(options: BridgeOptions?): BridgeSession = unsupported("bridge")

    private fun unsupported(feature: String): Nothing = error("android: $feature is not supported by sing_box")

    private fun InterfaceAddress.toPrefix(): String = if (address is Inet6Address) {
        "${Inet6Address.getByAddress(address.address).hostAddress}/$networkPrefixLength"
    } else {
        "${address.hostAddress}/$networkPrefixLength"
    }

    private companion object {
        const val TAG = "sing_box"
    }
}
