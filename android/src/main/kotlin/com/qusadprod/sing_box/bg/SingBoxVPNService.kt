package com.qusadprod.sing_box.bg

import android.content.Intent
import android.content.pm.PackageManager.NameNotFoundException
import android.net.ProxyInfo
import android.net.VpnService
import android.os.Build
import android.os.IBinder
import io.nekohasekai.libbox.Notification
import io.nekohasekai.libbox.TunOptions
import com.qusadprod.sing_box.BypassManager
import com.qusadprod.sing_box.DnsManager
import com.qusadprod.sing_box.ktx.toIpPrefix
import com.qusadprod.sing_box.ktx.toList
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import android.util.Log

/**
 * VPN сервис для sing-box
 * Скопировано и адаптировано из sing-box-for-android
 * Android Service для работы с VPN
 */
class SingBoxVPNService : VpnService(), io.nekohasekai.libbox.PlatformInterface {

    companion object {
        private const val TAG = "SingBoxVPNService"
        const val ACTION_START = "com.qusadprod.sing_box.START"
        const val ACTION_STOP = "com.qusadprod.sing_box.STOP"
        const val ACTION_RELOAD = "com.qusadprod.sing_box.RELOAD"
        const val EXTRA_CONFIG = "config"
        const val EXTRA_DISABLE_MEMORY_LIMIT = "disableMemoryLimit"
    }

    private lateinit var networkMonitor: DefaultNetworkMonitor
    private lateinit var localResolver: LocalResolver
    private lateinit var platformInterface: PlatformInterfaceWrapper
    private lateinit var singBoxService: SingBoxService
    private lateinit var bypassManager: BypassManager
    private lateinit var dnsManager: DnsManager
    private lateinit var blockManager: com.qusadprod.sing_box.BlockManager
    
    // CoroutineScope для управления жизненным циклом корутин
    private val serviceScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    var systemProxyAvailable = false
    var systemProxyEnabled = false

    override fun onCreate() {
        super.onCreate()
        // Инициализация компонентов
        networkMonitor = DefaultNetworkMonitor(this)
        localResolver = LocalResolver(this, networkMonitor)
        platformInterface = PlatformInterfaceWrapper(this, networkMonitor, localResolver)
        singBoxService = SingBoxService(this, this, platformInterface, networkMonitor)
        bypassManager = BypassManager(this)
        dnsManager = DnsManager(this)
        blockManager = com.qusadprod.sing_box.BlockManager(this)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                val config = intent.getStringExtra(EXTRA_CONFIG)
                val disableMemoryLimit = intent.getBooleanExtra(EXTRA_DISABLE_MEMORY_LIMIT, false)
                return singBoxService.onStartCommand(config, disableMemoryLimit)
            }
            ACTION_STOP -> {
                singBoxService.stopService()
                stopSelf()
                return START_NOT_STICKY
            }
            ACTION_RELOAD -> {
                // Перезапуск VPN для применения изменений (bypass, DNS и т.д.)
                serviceScope.launch(Dispatchers.Main) {
                    singBoxService.serviceReload()
                }
                return START_NOT_STICKY
            }
        }
        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent): IBinder {
        val binder = super.onBind(intent)
        return binder ?: super.onBind(intent)
    }

    override fun onDestroy() {
        singBoxService.cleanup()
        singBoxService.onDestroy()
        // Отменяем все корутины при уничтожении сервиса
        serviceScope.cancel()
        super.onDestroy()
    }

    override fun onRevoke() {
        serviceScope.launch(Dispatchers.Main) {
            singBoxService.onRevoke()
        }
        // Отменяем все корутины при отзыве разрешения
        serviceScope.cancel()
    }

    override fun autoDetectInterfaceControl(fd: Int) {
        protect(fd)
    }

    override fun openTun(options: TunOptions): Int {
        if (prepare(this) != null) {
            throw SecurityException("android: missing vpn permission")
        }

        val builder = Builder()
            .setSession("sing-box")
            .setMtu(options.mtu)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            builder.setMetered(false)
        }

        val inet4Address = options.inet4Address
        while (inet4Address.hasNext()) {
            val address = inet4Address.next()
            builder.addAddress(address.address(), address.prefix())
        }

        val inet6Address = options.inet6Address
        while (inet6Address.hasNext()) {
            val address = inet6Address.next()
            builder.addAddress(address.address(), address.prefix())
        }

        if (options.autoRoute) {
            // Применяем DNS серверы из DnsManager (если есть), иначе используем из options
            val customDnsServers = dnsManager.getDnsServers()
            if (customDnsServers.isNotEmpty()) {
                // Используем DNS серверы из DnsManager
                for (dnsServer in customDnsServers) {
                    builder.addDnsServer(dnsServer)
                }
            } else {
                // Используем DNS из options (по умолчанию)
                builder.addDnsServer(options.dnsServerAddress.value)
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                val inet4RouteAddress = options.inet4RouteAddress
                if (inet4RouteAddress.hasNext()) {
                    while (inet4RouteAddress.hasNext()) {
                        builder.addRoute(inet4RouteAddress.next().toIpPrefix())
                    }
                } else if (options.inet4Address.hasNext()) {
                    builder.addRoute("0.0.0.0", 0)
                }

                val inet6RouteAddress = options.inet6RouteAddress
                if (inet6RouteAddress.hasNext()) {
                    while (inet6RouteAddress.hasNext()) {
                        builder.addRoute(inet6RouteAddress.next().toIpPrefix())
                    }
                } else if (options.inet6Address.hasNext()) {
                    builder.addRoute("::", 0)
                }

                val inet4RouteExcludeAddress = options.inet4RouteExcludeAddress
                while (inet4RouteExcludeAddress.hasNext()) {
                    builder.excludeRoute(inet4RouteExcludeAddress.next().toIpPrefix())
                }

                val inet6RouteExcludeAddress = options.inet6RouteExcludeAddress
                while (inet6RouteExcludeAddress.hasNext()) {
                    builder.excludeRoute(inet6RouteExcludeAddress.next().toIpPrefix())
                }
            } else {
                val inet4RouteAddress = options.inet4RouteRange
                if (inet4RouteAddress.hasNext()) {
                    while (inet4RouteAddress.hasNext()) {
                        val address = inet4RouteAddress.next()
                        builder.addRoute(address.address(), address.prefix())
                    }
                }

                val inet6RouteAddress = options.inet6RouteRange
                if (inet6RouteAddress.hasNext()) {
                    while (inet6RouteAddress.hasNext()) {
                        val address = inet6RouteAddress.next()
                        builder.addRoute(address.address(), address.prefix())
                    }
                }
            }

            // Применяем bypass списки из BypassManager (исключаем из VPN - трафик идет напрямую)
            val bypassApps = bypassManager.getBypassApps()
            for (packageName in bypassApps) {
                try {
                    builder.addAllowedApplication(packageName)
                } catch (_: NameNotFoundException) {
                    // Игнорируем несуществующие приложения
                }
            }
            
            // Применяем блокировку приложений из BlockManager (блокируем трафик)
            blockManager.getBlockedApps().forEach { packageName ->
                try {
                    builder.addDisallowedApplication(packageName)
                } catch (_: NameNotFoundException) {
                    // Игнорируем несуществующие приложения
                }
            }
            
            // Применяем bypass подсети
            val bypassSubnets = bypassManager.getBypassSubnets()
            for (subnet in bypassSubnets) {
                try {
                    // Парсим CIDR нотацию (например, "192.168.1.0/24")
                    val parts = subnet.split("/")
                    if (parts.size == 2) {
                        val address = parts[0]
                        val prefixLength = parts[1].toIntOrNull()
                        if (prefixLength != null && prefixLength in 0..32) {
                            builder.excludeRoute(address, prefixLength)
                        }
                    }
                } catch (e: Exception) {
                    // Игнорируем ошибки парсинга подсети
                }
            }
            
            // Обрабатываем include/exclude пакеты из options (если есть)
            val includePackage = options.includePackage
            if (includePackage.hasNext()) {
                while (includePackage.hasNext()) {
                    try {
                        builder.addAllowedApplication(includePackage.next())
                    } catch (_: NameNotFoundException) {
                    }
                }
            }

            val excludePackage = options.excludePackage
            if (excludePackage.hasNext()) {
                while (excludePackage.hasNext()) {
                    try {
                        builder.addDisallowedApplication(excludePackage.next())
                    } catch (_: NameNotFoundException) {
                    }
                }
            }
        }

        if (options.isHTTPProxyEnabled && Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            systemProxyAvailable = true
            // Получаем состояние системного прокси из настроек или проверяем через API
            systemProxyEnabled = getSystemProxyEnabledState()
            if (systemProxyEnabled) builder.setHttpProxy(
                ProxyInfo.buildDirectProxy(
                    options.httpProxyServer,
                    options.httpProxyServerPort,
                    options.httpProxyBypassDomain.toList()
                )
            )
        } else {
            systemProxyAvailable = false
            systemProxyEnabled = false
        }

        val pfd = builder.establish() ?: throw IllegalStateException(
            "android: the application is not prepared or is revoked"
        )
        singBoxService.fileDescriptor = pfd
        return pfd.fd
    }

    override fun writeLog(message: String) = singBoxService.writeLog(message)

    override fun sendNotification(notification: Notification) =
        singBoxService.sendNotification(notification)
    
    /**
     * Получить состояние системного прокси
     * Сначала проверяет настройки из SettingsManager, затем через Android API
     */
    private fun getSystemProxyEnabledState(): Boolean {
        // Пробуем получить из настроек
        try {
            val settingsManager = com.qusadprod.sing_box.SettingsManager(this)
            val settings = settingsManager.getSettings()
            val proxyEnabled = settings["systemProxyEnabled"] as? Boolean
            if (proxyEnabled != null) {
                return proxyEnabled
            }
        } catch (e: Exception) {
            // Игнорируем ошибки при чтении настроек, но логируем для отладки
            Log.w("SingBoxVPNService", "Error reading systemProxyEnabled from settings", e)
        }
        
        // Если в настройках нет, проверяем через Android API
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            try {
                val connectivityManager = getSystemService(Context.CONNECTIVITY_SERVICE) as? android.net.ConnectivityManager
                if (connectivityManager == null) {
                    return false
                }
                val activeNetwork = connectivityManager.activeNetwork
                
                if (activeNetwork != null) {
                    val linkProperties = connectivityManager.getLinkProperties(activeNetwork)
                    if (linkProperties != null) {
                        val proxyInfo = linkProperties.httpProxy
                        // Если proxyInfo не null и не DIRECT, значит прокси настроен
                        return proxyInfo != null && proxyInfo != ProxyInfo.buildDirectProxy(null, 0)
                    }
                }
            } catch (e: Exception) {
                // В случае ошибки считаем, что прокси отключен, но логируем для отладки
                Log.w("SingBoxVPNService", "Error checking system proxy via Android API", e)
            }
        }
        
        return false
    }

    // Делегирование методов PlatformInterface к platformInterface
    override fun usePlatformAutoDetectInterfaceControl(): Boolean = platformInterface.usePlatformAutoDetectInterfaceControl()
    override fun useProcFS(): Boolean = platformInterface.useProcFS()
    override fun findConnectionOwner(ipProtocol: Int, sourceAddress: String, sourcePort: Int, destinationAddress: String, destinationPort: Int): Int = platformInterface.findConnectionOwner(ipProtocol, sourceAddress, sourcePort, destinationAddress, destinationPort)
    override fun packageNameByUid(uid: Int): String = platformInterface.packageNameByUid(uid)
    override fun uidByPackageName(packageName: String): Int = platformInterface.uidByPackageName(packageName)
    override fun startDefaultInterfaceMonitor(listener: io.nekohasekai.libbox.InterfaceUpdateListener) = platformInterface.startDefaultInterfaceMonitor(listener)
    override fun closeDefaultInterfaceMonitor(listener: io.nekohasekai.libbox.InterfaceUpdateListener) = platformInterface.closeDefaultInterfaceMonitor(listener)
    override fun getInterfaces(): io.nekohasekai.libbox.NetworkInterfaceIterator = platformInterface.getInterfaces()
    override fun underNetworkExtension(): Boolean = platformInterface.underNetworkExtension()
    override fun includeAllNetworks(): Boolean = platformInterface.includeAllNetworks()
    override fun clearDNSCache() = platformInterface.clearDNSCache()
    override fun readWIFIState(): io.nekohasekai.libbox.WIFIState? = platformInterface.readWIFIState()
    override fun localDNSTransport(): io.nekohasekai.libbox.LocalDNSTransport? = platformInterface.localDNSTransport()
    override fun systemCertificates(): io.nekohasekai.libbox.StringIterator = platformInterface.systemCertificates()
}

