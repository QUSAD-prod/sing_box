/*
 * Service lifecycle adapted from sing-box-for-android (SFA) bg/BoxService.kt and
 * bg/VPNService.kt (GPL-3.0-or-later).
 */
package com.qusadprod.sing_box.service

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.net.IpPrefix
import android.net.ProxyInfo
import android.net.Uri
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import android.os.PowerManager
import android.util.Log
import androidx.annotation.MainThread
import androidx.annotation.RequiresApi
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.qusadprod.sing_box.core.AppInfo
import com.qusadprod.sing_box.core.CoreNotifications
import com.qusadprod.sing_box.core.LibboxRuntime
import com.qusadprod.sing_box.core.Paths
import com.qusadprod.sing_box.core.ServiceSettings
import com.qusadprod.sing_box.core.ServiceState
import com.qusadprod.sing_box.core.ServiceStatus
import com.qusadprod.sing_box.core.SingBoxError
import com.qusadprod.sing_box.core.libboxMessage
import com.qusadprod.sing_box.core.toList
import io.nekohasekai.libbox.CommandServer
import io.nekohasekai.libbox.CommandServerHandler
import io.nekohasekai.libbox.Libbox
import io.nekohasekai.libbox.Notification
import io.nekohasekai.libbox.OverrideOptions
import io.nekohasekai.libbox.RoutePrefix
import io.nekohasekai.libbox.RoutePrefixIterator
import io.nekohasekai.libbox.SystemProxyStatus
import io.nekohasekai.libbox.TunOptions
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import java.net.InetAddress

/**
 * Foreground `VpnService` hosting the libbox command server and the box
 * instance. Runs in the application's main process; its state is published
 * through [ServiceState].
 */
class SingBoxVpnService : VpnService(), CommandServerHandler {
    companion object {
        private const val TAG = "sing_box"

        /** Android 11+ package visibility also hides apps from VpnService.Builder and package_name rules. */
        private const val VISIBILITY_HINT =
            "; on Android 11+ declare QUERY_ALL_PACKAGES or a <queries> entry for it in the app manifest"

        @Volatile
        internal var instance: SingBoxVpnService? = null
            private set

        /** Explicit stop broadcast (notification action), restricted to our package. */
        internal fun actionStop(context: Context) = "${context.packageName}.sing_box.STOP"

        /**
         * Asks the system to start the service; it reads the last config. Throws
         * when the platform refuses to start a foreground service (e.g. from the
         * background on Android 12+).
         */
        internal fun start(context: Context) {
            val intent = Intent(context, SingBoxVpnService::class.java).setAction(ACTION_START)
            ContextCompat.startForegroundService(context.applicationContext, intent)
        }

        internal const val ACTION_START = "com.qusadprod.sing_box.action.START"

        /** Set when the plugin stops a start whose service has not been created yet. */
        @Volatile
        private var pendingStop = false

        internal fun cancelPendingStop() {
            pendingStop = false
        }

        /**
         * Stops a start requested with [start] before the service exists: the state
         * becomes `Stopped` now and the service quits as soon as it is created.
         */
        internal fun requestPendingStop(context: Context) {
            pendingStop = true
            ServiceSettings(context).wasRunning = false
            ServiceState.update { it.copy(status = ServiceStatus.Stopped, startedAt = null) }
        }

        /** Shared by all service instances so that cleanup survives `onDestroy`. */
        private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    }

    private lateinit var settings: ServiceSettings
    private lateinit var platform: PlatformInterfaceImpl
    private lateinit var notification: ServiceNotification
    private val lifecycle = Mutex()
    private val idleUpdates = Channel<Boolean>(Channel.CONFLATED)

    @Volatile
    private var commandServer: CommandServer? = null

    @Volatile
    private var tunFd: ParcelFileDescriptor? = null
    private var pendingStart = false
    private var receiverRegistered = false

    /** A [doStart] of this instance is queued or running (main thread only). */
    private var startInProgress = false

    @Volatile
    internal var systemProxyAvailable = false

    /** Always-on VPN with "Block connections without VPN": stopping would cut the device off. */
    internal val isLockdown: Boolean
        get() = Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && isLockdownEnabled

    override fun onCreate() {
        super.onCreate()
        instance = this
        settings = ServiceSettings(this)
        platform = PlatformInterfaceImpl(this)
        notification = ServiceNotification(this, scope)
        registerReceivers()
        scope.launch(Dispatchers.IO) {
            for (idle in idleUpdates) {
                val server = commandServer ?: continue
                runCatching { if (idle) server.pause() else server.wake() }
            }
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == actionStop(this)) {
            requestStop(userInitiated = true)
        } else {
            // ACTION_START from the plugin / boot receiver / tile, or a system start
            // (always-on VPN: action android.net.VpnService, sticky restart: null intent).
            requestStart()
        }
        return START_NOT_STICKY
    }

    override fun onRevoke() {
        // Another VPN app took over or the user revoked the permission.
        requestStop(error = "android: VPN permission revoked", userInitiated = false)
    }

    override fun onDestroy() {
        unregisterReceivers()
        idleUpdates.close()
        if (instance === this) instance = null
        val server = commandServer
        if (server != null || ServiceState.status != ServiceStatus.Stopped) {
            // Destroyed without a completed stop: release everything.
            commandServer = null
            val fd = tunFd
            tunFd = null
            scope.launch(Dispatchers.IO) {
                runCatching { fd?.close() }
                DefaultNetworkMonitor.stop()
                server?.let {
                    runCatching { it.closeService() }
                    runCatching { it.close() }
                }
                ServiceState.update { it.copy(status = ServiceStatus.Stopped, startedAt = null) }
            }
        }
        super.onDestroy()
    }

    // ---------------------------------------------------------------------------------------
    // Lifecycle
    // ---------------------------------------------------------------------------------------

    @MainThread
    private fun requestStart() {
        notification.update(settings.notificationOptions)
        try {
            // Must happen right after startForegroundService(), also for duplicate starts.
            notification.show()
        } catch (e: Exception) {
            Log.e(TAG, "startForeground", e)
            if (commandServer == null && !startInProgress) {
                ServiceState.update {
                    it.copy(
                        status = ServiceStatus.Stopped,
                        startedAt = null,
                        error = "android: cannot start foreground service: ${e.libboxMessage}",
                    )
                }
                stopSelf()
            }
            return
        }
        if (pendingStop) {
            // The plugin stopped this start before the service existed.
            pendingStop = false
            if (commandServer == null && !startInProgress) {
                notification.close()
                stopSelf()
                return
            }
        }
        when (ServiceState.status) {
            ServiceStatus.Stopped -> Unit
            ServiceStatus.Stopping -> {
                pendingStart = true
                return
            }
            ServiceStatus.Started -> return
            // The plugin reports `connecting` before the service is created.
            ServiceStatus.Starting -> if (startInProgress) return
        }
        startInProgress = true
        ServiceState.update { it.copy(status = ServiceStatus.Starting, startedAt = null) }
        scope.launch(Dispatchers.IO) {
            settings.wasRunning = true
            try {
                lifecycle.withLock { doStart() }
            } finally {
                withContext(Dispatchers.Main) { startInProgress = false }
            }
        }
    }

    private fun isStarting() = ServiceState.status == ServiceStatus.Starting

    private suspend fun doStart() {
        try {
            LibboxRuntime.ensureSetup(this)
            val config = Paths.readLastConfig(this)
                ?: error("android: no configuration, start the VPN from the app first")
            if (prepare(this) != null) error("android: missing VPN permission")
            if (!isStarting()) return
            DefaultNetworkMonitor.start(this)
            val server = commandServer ?: Libbox.newCommandServer(this, platform).also {
                it.start()
                commandServer = it
            }
            if (!isStarting()) return
            server.startOrReloadService(config, OverrideOptions())
            if (!isStarting()) return
            if (server.needWIFIState()) {
                Log.w(TAG, "configuration uses WIFI rules: reading the SSID needs location permission")
            }
            withContext(Dispatchers.Main) {
                if (ServiceState.status == ServiceStatus.Starting) {
                    val now = System.currentTimeMillis()
                    ServiceState.update {
                        it.copy(status = ServiceStatus.Started, startedAt = now, error = null, generation = it.generation + 1)
                    }
                    notification.refresh()
                    notification.startTrafficUpdates()
                    updateIdleMode()
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "start service", e)
            val message = e.libboxMessage
            withContext(Dispatchers.Main) {
                if (ServiceState.status == ServiceStatus.Starting) requestStop(error = message, userInitiated = false)
            }
        }
    }

    /**
     * Stops the box instance and the service. [error] is published in the status
     * stream when the stop is caused by a failure.
     */
    @MainThread
    internal fun requestStop(error: String? = null, userInitiated: Boolean) {
        if (userInitiated) pendingStart = false
        when (ServiceState.status) {
            ServiceStatus.Stopped -> {
                if (commandServer == null) stopSelf()
                return
            }
            ServiceStatus.Stopping -> return
            else -> Unit
        }
        ServiceState.update { it.copy(status = ServiceStatus.Stopping, error = error) }
        notification.close()
        val server = commandServer
        scope.launch(Dispatchers.IO) {
            if (userInitiated) settings.wasRunning = false
            // Interrupts a start that is still in progress (libbox handles the concurrency).
            server?.let { runCatching { it.closeService() } }
            lifecycle.withLock {
                closeTun()
                DefaultNetworkMonitor.stop()
                commandServer?.let {
                    runCatching { it.closeService() }.onFailure { e -> Log.w(TAG, "close service", e) }
                    runCatching { it.close() }
                }
                commandServer = null
            }
            withContext(Dispatchers.Main) {
                ServiceState.update { it.copy(status = ServiceStatus.Stopped, startedAt = null, error = error) }
                if (pendingStart) {
                    pendingStart = false
                    requestStart()
                } else {
                    stopSelf()
                }
            }
        }
    }

    /**
     * Reloads the running box instance with the last config. Throws
     * [SingBoxError] (`SERVICE_NOT_RUNNING` / `START_FAILED`); a failed reload
     * stops the service with the error.
     */
    internal suspend fun reload() {
        if (!ServiceState.isRunning) throw SingBoxError.notRunning()
        lifecycle.withLock {
            val server = commandServer
            if (!ServiceState.isRunning || server == null) throw SingBoxError.notRunning()
            val config = Paths.readLastConfig(this)
                ?: throw SingBoxError(SingBoxError.START_FAILED, "android: no configuration")
            try {
                server.startOrReloadService(config, OverrideOptions())
            } catch (e: Exception) {
                val message = e.libboxMessage
                withContext(Dispatchers.Main) { requestStop(error = message, userInitiated = false) }
                throw SingBoxError(SingBoxError.START_FAILED, message)
            }
            withContext(Dispatchers.Main) {
                ServiceState.update {
                    if (it.status == ServiceStatus.Started) it.copy(error = null, generation = it.generation + 1) else it
                }
            }
        }
    }

    private fun closeTun() {
        val fd = tunFd
        tunFd = null
        runCatching { fd?.close() }
    }

    // ---------------------------------------------------------------------------------------
    // CommandServerHandler (called by libbox from gRPC handlers: never block on shutdown)
    // ---------------------------------------------------------------------------------------

    override fun serviceStop() {
        scope.launch(Dispatchers.Main) { requestStop(userInitiated = true) }
    }

    override fun serviceReload() {
        runBlocking(Dispatchers.IO) { reload() }
    }

    override fun getSystemProxyStatus(): SystemProxyStatus = SystemProxyStatus().apply {
        available = systemProxyAvailable
        enabled = systemProxyAvailable
    }

    override fun setSystemProxyEnabled(isEnabled: Boolean) {
        // The HTTP proxy of the tun inbound is applied whenever the config enables it.
    }

    override fun triggerNativeCrash() {
        Log.w(TAG, "ignoring triggerNativeCrash request")
    }

    override fun writeDebugMessage(message: String?) {
        Log.d("sing-box", message ?: "")
    }

    override fun connectSSHAgent(): Int = -1

    // ---------------------------------------------------------------------------------------
    // Tun
    // ---------------------------------------------------------------------------------------

    internal fun openTun(options: TunOptions): Int {
        if (prepare(this) != null) error("android: missing VPN permission")
        val notificationOptions = settings.notificationOptions
        val builder = Builder()
            .setSession(notificationOptions.sessionName ?: AppInfo.label(this))
            .setMtu(options.mtu)
        AppInfo.launchPendingIntent(this, 1)?.let { builder.setConfigureIntent(it) }
        // false = "metered only if the underlying network is" (set below), not "always unmetered".
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            builder.setMetered(false)
            DefaultNetworkMonitor.defaultNetwork?.let { builder.setUnderlyingNetworks(arrayOf(it)) }
        }

        val inet4Address = options.inet4Address.toPrefixes()
        val inet6Address = options.inet6Address.toPrefixes()
        for (address in inet4Address + inet6Address) {
            builder.addAddress(address.address(), address.prefix())
        }

        if (options.autoRoute) {
            if (options.dnsMode?.value != Libbox.DNSModeDisabled) {
                runCatching { options.dnsServerAddress.toList() }.getOrDefault(emptyList()).forEach {
                    builder.addDnsServer(it)
                }
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                addRoutesTiramisu(builder, options, inet4Address.isNotEmpty(), inet6Address.isNotEmpty())
            } else {
                for (route in options.inet4RouteRange.toPrefixes() + options.inet6RouteRange.toPrefixes()) {
                    builder.addRoute(route.address(), route.prefix())
                }
            }
            val includePackages = options.includePackage.toList()
            val excludePackages = options.excludePackage.toList()
            var allowed = 0
            for (packageName in includePackages) {
                // Recent Android versions accept unknown packages silently, so check first.
                if (!isPackageVisible(packageName)) {
                    Log.w(TAG, "include_package: $packageName is not installed or not visible$VISIBILITY_HINT")
                    continue
                }
                try {
                    builder.addAllowedApplication(packageName)
                    allowed++
                } catch (_: PackageManager.NameNotFoundException) {
                    Log.w(TAG, "include_package: $packageName is not installed or not visible$VISIBILITY_HINT")
                }
            }
            if (includePackages.isNotEmpty() && allowed == 0) {
                // Without any allowed application the VPN would capture every app.
                error(
                    "android: none of the include_package apps is installed or visible to the app " +
                        "(${includePackages.joinToString()})$VISIBILITY_HINT",
                )
            }
            if (includePackages.isEmpty()) {
                for (packageName in excludePackages) {
                    if (!isPackageVisible(packageName)) {
                        Log.w(TAG, "exclude_package: $packageName is not installed or not visible$VISIBILITY_HINT")
                        continue
                    }
                    try {
                        builder.addDisallowedApplication(packageName)
                    } catch (_: PackageManager.NameNotFoundException) {
                        Log.w(TAG, "exclude_package: $packageName is not installed or not visible$VISIBILITY_HINT")
                    }
                }
            }
        }

        systemProxyAvailable = false
        if (options.isHTTPProxyEnabled && Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            builder.setHttpProxy(
                ProxyInfo.buildDirectProxy(
                    options.httpProxyServer,
                    options.httpProxyServerPort,
                    options.httpProxyBypassDomain.toList(),
                ),
            )
            systemProxyAvailable = true
        }

        val pfd = builder.establish() ?: error("android: the application is not prepared or is revoked")
        val previous = tunFd
        tunFd = pfd
        // establish() replaced the previous interface (reload); release its descriptor.
        runCatching { previous?.close() }
        return pfd.fd
    }

    @Suppress("DEPRECATION")
    private fun isPackageVisible(packageName: String): Boolean =
        runCatching { packageManager.getApplicationInfo(packageName, 0) }.isSuccess

    @RequiresApi(Build.VERSION_CODES.TIRAMISU)
    private fun addRoutesTiramisu(builder: Builder, options: TunOptions, hasInet4: Boolean, hasInet6: Boolean) {
        val inet4Routes = options.inet4RouteAddress.toPrefixes()
        if (inet4Routes.isNotEmpty()) {
            inet4Routes.forEach { builder.addRoute(it.toIpPrefix()) }
        } else if (hasInet4) {
            builder.addRoute("0.0.0.0", 0)
        }
        val inet6Routes = options.inet6RouteAddress.toPrefixes()
        if (inet6Routes.isNotEmpty()) {
            inet6Routes.forEach { builder.addRoute(it.toIpPrefix()) }
        } else if (hasInet6) {
            builder.addRoute("::", 0)
        }
        (options.inet4RouteExcludeAddress.toPrefixes() + options.inet6RouteExcludeAddress.toPrefixes()).forEach {
            builder.excludeRoute(it.toIpPrefix())
        }
    }

    private fun RoutePrefixIterator?.toPrefixes(): List<RoutePrefix> {
        if (this == null) return emptyList()
        val result = mutableListOf<RoutePrefix>()
        while (hasNext()) result.add(next())
        return result
    }

    @RequiresApi(Build.VERSION_CODES.TIRAMISU)
    private fun RoutePrefix.toIpPrefix() = IpPrefix(InetAddress.getByName(address()), prefix())

    // ---------------------------------------------------------------------------------------
    // Core notifications (PlatformInterface.sendNotification)
    // ---------------------------------------------------------------------------------------

    internal fun showCoreNotification(notification: Notification) {
        CoreNotifications.publish(
            mapOf(
                "identifier" to notification.identifier,
                "typeName" to notification.typeName,
                "typeId" to notification.typeID,
                "title" to notification.title,
                "subtitle" to notification.subtitle,
                "body" to notification.body,
                "openUrl" to notification.openURL,
            ),
        )
        val channelId = "sing_box_core_${notification.typeID}"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            getSystemService(NotificationManager::class.java)?.createNotificationChannel(
                NotificationChannel(
                    channelId,
                    notification.typeName?.takeIf { it.isNotBlank() } ?: "sing-box",
                    NotificationManager.IMPORTANCE_DEFAULT,
                ),
            )
        }
        val options = settings.notificationOptions
        val builder = NotificationCompat.Builder(this, channelId)
            .setShowWhen(false)
            .setContentTitle(notification.title)
            .setContentText(notification.body)
            .setOnlyAlertOnce(true)
            .setSmallIcon(AppInfo.iconResource(this, options.icon))
            .setCategory(NotificationCompat.CATEGORY_EVENT)
            .setAutoCancel(true)
        if (!notification.subtitle.isNullOrBlank()) builder.setSubText(notification.subtitle)
        val openUrl = notification.openURL
        val contentIntent = if (!openUrl.isNullOrBlank()) {
            PendingIntent.getActivity(
                this,
                2,
                Intent(Intent.ACTION_VIEW, Uri.parse(openUrl)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                AppInfo.immutableFlag or PendingIntent.FLAG_UPDATE_CURRENT,
            )
        } else {
            AppInfo.launchPendingIntent(this)
        }
        contentIntent?.let { builder.setContentIntent(it) }
        runCatching {
            @Suppress("MissingPermission")
            NotificationManagerCompat.from(this).notify(notification.identifier, notification.typeID, builder.build())
        }.onFailure { Log.w(TAG, "show notification: ${it.message}") }
    }

    internal fun cancelCoreNotification(identifier: String, typeID: Int) {
        NotificationManagerCompat.from(this).cancel(identifier, typeID)
    }

    // ---------------------------------------------------------------------------------------
    // Receivers: stop action, doze
    // ---------------------------------------------------------------------------------------

    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            when (intent.action) {
                actionStop(context) -> requestStop(userInitiated = true)
                PowerManager.ACTION_DEVICE_IDLE_MODE_CHANGED -> updateIdleMode()
            }
        }
    }

    private fun updateIdleMode() {
        val powerManager = getSystemService(PowerManager::class.java) ?: return
        if (commandServer != null) idleUpdates.trySend(powerManager.isDeviceIdleMode)
    }

    private fun registerReceivers() {
        if (receiverRegistered) return
        ContextCompat.registerReceiver(
            this,
            receiver,
            IntentFilter().apply {
                addAction(actionStop(this@SingBoxVpnService))
                addAction(PowerManager.ACTION_DEVICE_IDLE_MODE_CHANGED)
            },
            ContextCompat.RECEIVER_NOT_EXPORTED,
        )
        receiverRegistered = true
    }

    private fun unregisterReceivers() {
        if (!receiverRegistered) return
        runCatching { unregisterReceiver(receiver) }
        receiverRegistered = false
    }
}
