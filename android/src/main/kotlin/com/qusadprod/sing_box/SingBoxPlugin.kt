package com.qusadprod.sing_box

import android.Manifest
import android.app.Activity
import android.app.StatusBarManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.drawable.Icon
import android.net.VpnService
import android.os.Build
import android.provider.Settings
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.qusadprod.sing_box.core.AppInfo
import com.qusadprod.sing_box.core.KeyValueStorage
import com.qusadprod.sing_box.core.LibboxRuntime
import com.qusadprod.sing_box.core.NotificationOptions
import com.qusadprod.sing_box.core.Paths
import com.qusadprod.sing_box.core.ServiceSettings
import com.qusadprod.sing_box.core.ServiceState
import com.qusadprod.sing_box.core.ServiceStatus
import com.qusadprod.sing_box.core.SingBoxError
import com.qusadprod.sing_box.core.libboxMessage
import com.qusadprod.sing_box.plugin.ClashModeStreamHandler
import com.qusadprod.sing_box.plugin.ConnectionsStreamHandler
import com.qusadprod.sing_box.plugin.GroupsStreamHandler
import com.qusadprod.sing_box.plugin.LogsStreamHandler
import com.qusadprod.sing_box.plugin.NetworkQualityStreamHandler
import com.qusadprod.sing_box.plugin.NotificationsStreamHandler
import com.qusadprod.sing_box.plugin.OutboundsStreamHandler
import com.qusadprod.sing_box.plugin.StatsStreamHandler
import com.qusadprod.sing_box.plugin.StatusStreamHandler
import com.qusadprod.sing_box.plugin.StunStreamHandler
import com.qusadprod.sing_box.service.NativePing
import com.qusadprod.sing_box.service.ProbeCore
import com.qusadprod.sing_box.service.ServiceNotification
import com.qusadprod.sing_box.service.SingBoxTileService
import com.qusadprod.sing_box.service.SingBoxVpnService
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import io.nekohasekai.libbox.CommandClient
import io.nekohasekai.libbox.Libbox
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * Flutter plugin entry point: implements the method channel `sing_box` and the
 * event channels of `doc/platform_channel.md`. The VPN itself runs in
 * [SingBoxVpnService]; this class only talks to it and to libbox.
 */
class SingBoxPlugin :
    FlutterPlugin,
    ActivityAware,
    MethodChannel.MethodCallHandler,
    PluginRegistry.ActivityResultListener,
    PluginRegistry.RequestPermissionsResultListener {
    private lateinit var context: Context
    private lateinit var channel: MethodChannel
    private val eventChannels = mutableListOf<EventChannel>()
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    private var activityBinding: ActivityPluginBinding? = null
    private var vpnPermissionResult: MethodChannel.Result? = null
    private var notificationPermissionResult: MethodChannel.Result? = null
    private var initialized = false

    // ---------------------------------------------------------------------------------------
    // FlutterPlugin / ActivityAware
    // ---------------------------------------------------------------------------------------

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "sing_box")
        channel.setMethodCallHandler(this)
        val handlers = mapOf(
            "status" to StatusStreamHandler(),
            "stats" to StatsStreamHandler(scope),
            "logs" to LogsStreamHandler(scope),
            "groups" to GroupsStreamHandler(scope),
            "outbounds" to OutboundsStreamHandler(scope),
            "clash_mode" to ClashModeStreamHandler(scope),
            "connections" to ConnectionsStreamHandler(scope),
            "notifications" to NotificationsStreamHandler(),
            "network_quality" to NetworkQualityStreamHandler(context, scope),
            "stun" to StunStreamHandler(context, scope),
        )
        for ((name, handler) in handlers) {
            eventChannels += EventChannel(binding.binaryMessenger, "sing_box/$name").apply {
                setStreamHandler(handler)
            }
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        for (eventChannel in eventChannels) eventChannel.setStreamHandler(null)
        eventChannels.clear()
        scope.cancel()
        Thread { ProbeCore.stop() }.start()
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
        binding.addActivityResultListener(this)
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        // The pending requests are delivered to the recreated Activity.
        detachActivity()
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        onAttachedToActivity(binding)
    }

    override fun onDetachedFromActivity() {
        detachActivity()
        // No Activity will deliver the results any more: answer with the current state.
        vpnPermissionResult?.success(hasVpnPermission())
        vpnPermissionResult = null
        notificationPermissionResult?.success(hasNotificationPermission())
        notificationPermissionResult = null
    }

    private fun detachActivity() {
        activityBinding?.removeActivityResultListener(this)
        activityBinding?.removeRequestPermissionsResultListener(this)
        activityBinding = null
    }

    private val activity: Activity? get() = activityBinding?.activity

    // ---------------------------------------------------------------------------------------
    // Method channel
    // ---------------------------------------------------------------------------------------

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val method = call.method
        if (method != "getPlatformVersion" && method != "initialize" && !initialized) {
            result.error(SingBoxError.NOT_INITIALIZED, SingBoxError.notInitialized().message, null)
            return
        }
        when (method) {
            "initialize" -> respond(result) { initialize(call) }
            "getPlatformVersion" -> result.success("Android ${Build.VERSION.RELEASE}")
            "getSingBoxVersion" -> respond(result) { io { Libbox.version() } }
            "checkConfig" -> respond(result) {
                checkConfig(call.requireString("config"))
                null
            }
            "formatConfig" -> respond(result) { formatConfig(call.requireString("config")) }
            "hasVpnPermission" -> result.success(hasVpnPermission())
            "requestVpnPermission" -> requestVpnPermission(result)
            "hasNotificationPermission" -> result.success(hasNotificationPermission())
            "requestNotificationPermission" -> requestNotificationPermission(result)
            "openVpnSettings" -> respond(result) {
                openVpnSettings()
                null
            }
            "requestAddQuickSettingsTile" -> requestAddQuickSettingsTile(call.argument<String>("label"), result)
            "start" -> respond(result) {
                start(
                    call.requireString("config"),
                    oomKiller = call.argument<String>("oomKiller")
                        ?: if (call.argument<Boolean>("disableMemoryLimit") == true) {
                            ServiceSettings.OOM_KILLER_OFF
                        } else {
                            ServiceSettings.OOM_KILLER_PLATFORM_DEFAULT
                        },
                    memoryLimit = call.argument<Number>("memoryLimit")?.toLong() ?: 0L,
                )
                null
            }
            "stop" -> respond(result) {
                stop()
                null
            }
            "reload" -> respond(result) {
                reload(call.argument<String>("config"))
                null
            }
            "getStatus" -> result.success(ServiceState.status.wire)
            "getStartedAt" -> result.success(ServiceState.current.let { if (it.status == ServiceStatus.Started) it.startedAt else null })
            "getLastConfig" -> respond(result) { io { Paths.readLastConfig(context) } }
            "setServiceOptions" -> respond(result) {
                setServiceOptions(call.arguments as? Map<*, *> ?: emptyMap<Any, Any>())
                null
            }
            "selectOutbound" -> command(result) {
                it.selectOutbound(call.requireString("groupTag"), call.requireString("outboundTag"))
            }
            "urlTest" -> command(result) { it.urlTest(call.requireString("tag")) }
            "startProbe" -> respond(result) {
                val config = call.requireString("config")
                io { ProbeCore.start(context, config) }
                null
            }
            "stopProbe" -> respond(result) {
                io { ProbeCore.stop() }
                null
            }
            "pingServer" -> respond(result) {
                val method = call.requireString("method")
                val host = call.requireString("host")
                val port = call.argument<Number>("port")?.toInt()
                val timeoutMs = call.argument<Number>("timeoutMs")?.toInt() ?: 5000
                io { NativePing.ping(method, host, port, timeoutMs) }
            }
            "setClashMode" -> command(result) { it.setClashMode(call.requireString("mode")) }
            "closeConnection" -> command(result) { it.closeConnection(call.requireString("id")) }
            "closeAllConnections" -> command(result) { it.closeConnections() }
            "getSystemProxyStatus" -> commandResult(result) {
                val status = it.systemProxyStatus
                mapOf("available" to status.available, "enabled" to status.enabled)
            }
            "setSystemProxyEnabled" -> command(result) {
                it.setSystemProxyEnabled(call.argument<Boolean>("enabled") ?: false)
            }
            "clearLogs" -> command(result) { it.clearLogs() }
            "setGroupExpand" -> command(result) {
                it.setGroupExpand(call.requireString("groupTag"), call.argument<Boolean>("expand") ?: false)
            }
            "storageRead" -> respond(result) { io { KeyValueStorage(context).read(call.requireString("key")) } }
            "storageWrite" -> respond(result) {
                val key = call.requireString("key")
                val value = call.argument<String>("value")
                io { KeyValueStorage(context).write(key, value) }
                null
            }
            else -> result.notImplemented()
        }
    }

    /** Runs [block] on the main scope and reports its value or [SingBoxError]. */
    private fun respond(result: MethodChannel.Result, block: suspend () -> Any?) {
        scope.launch {
            try {
                result.success(block())
            } catch (e: SingBoxError) {
                result.error(e.code, e.message, null)
            } catch (e: Exception) {
                Log.e(TAG, "method call failed", e)
                result.error(SingBoxError.INTERNAL, e.libboxMessage, null)
            }
        }
    }

    private suspend fun <T> io(block: () -> T): T = withContext(Dispatchers.IO) { block() }

    private fun MethodCall.requireString(key: String): String =
        argument<String>(key) ?: throw SingBoxError.invalidArgument("Missing argument \"$key\"")

    // ---------------------------------------------------------------------------------------
    // Initialization and information
    // ---------------------------------------------------------------------------------------

    private suspend fun initialize(call: MethodCall): Map<String, Any?> {
        val settings = ServiceSettings(context)
        (call.argument<Number>("logMaxLines"))?.toInt()?.takeIf { it > 0 }?.let { settings.logMaxLines = it }
        call.argument<Boolean>("debug")?.let { settings.debug = it }
        val notificationOptions = NotificationOptions.fromMap(call.argument<Map<*, *>>("android"))
        settings.notificationOptions = notificationOptions
        ServiceNotification.createChannel(context, notificationOptions)
        io { LibboxRuntime.ensureSetup(context) }
        SingBoxTileService.install(context)
        initialized = true
        return mapOf(
            "singBoxVersion" to io { Libbox.version() },
            "status" to ServiceState.status.wire,
            "workingDirectory" to Paths.workingDir(context).path,
        )
    }

    private suspend fun checkConfig(config: String) = io {
        LibboxRuntime.ensureSetup(context)
        try {
            Libbox.checkConfig(config)
        } catch (e: Exception) {
            throw SingBoxError(SingBoxError.INVALID_CONFIG, e.libboxMessage)
        }
    }

    private suspend fun formatConfig(config: String): String = io {
        LibboxRuntime.ensureSetup(context)
        try {
            Libbox.formatConfig(config).value
        } catch (e: Exception) {
            throw SingBoxError(SingBoxError.INVALID_CONFIG, e.libboxMessage)
        }
    }

    // ---------------------------------------------------------------------------------------
    // Permissions
    // ---------------------------------------------------------------------------------------

    private fun hasVpnPermission(): Boolean = runCatching { VpnService.prepare(context) == null }.getOrDefault(false)

    private fun requestVpnPermission(result: MethodChannel.Result) {
        val intent = try {
            VpnService.prepare(context)
        } catch (e: Exception) {
            result.error(SingBoxError.INTERNAL, e.libboxMessage, null)
            return
        }
        if (intent == null) {
            result.success(true)
            return
        }
        val current = activity
        if (current == null) {
            result.error(SingBoxError.NO_ACTIVITY, SingBoxError.noActivity().message, null)
            return
        }
        if (vpnPermissionResult != null) {
            result.error(SingBoxError.INTERNAL, "A VPN permission request is already in progress", null)
            return
        }
        vpnPermissionResult = result
        try {
            current.startActivityForResult(intent, REQUEST_VPN)
        } catch (e: Exception) {
            vpnPermissionResult = null
            result.error(SingBoxError.INTERNAL, e.libboxMessage, null)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_VPN) return false
        val pending = vpnPermissionResult ?: return true
        vpnPermissionResult = null
        // RESULT_OK is not reliable on every OEM build; ask the system again.
        pending.success(resultCode == Activity.RESULT_OK || hasVpnPermission())
        return true
    }

    private fun hasNotificationPermission(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED

    private fun requestNotificationPermission(result: MethodChannel.Result) {
        if (hasNotificationPermission()) {
            result.success(true)
            return
        }
        val current = activity
        if (current == null) {
            result.error(SingBoxError.NO_ACTIVITY, SingBoxError.noActivity().message, null)
            return
        }
        if (notificationPermissionResult != null) {
            result.error(SingBoxError.INTERNAL, "A notification permission request is already in progress", null)
            return
        }
        notificationPermissionResult = result
        ActivityCompat.requestPermissions(current, arrayOf(Manifest.permission.POST_NOTIFICATIONS), REQUEST_NOTIFICATIONS)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ): Boolean {
        if (requestCode != REQUEST_NOTIFICATIONS) return false
        val pending = notificationPermissionResult ?: return true
        notificationPermissionResult = null
        pending.success(hasNotificationPermission())
        return true
    }

    private fun openVpnSettings() {
        val intent = Intent(Settings.ACTION_VPN_SETTINGS)
        val current = activity
        if (current != null) {
            current.startActivity(intent)
        } else {
            context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        }
    }

    private fun requestAddQuickSettingsTile(label: String?, result: MethodChannel.Result) {
        val current = activity
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU || current == null) {
            result.success("unsupported")
            return
        }
        val settings = ServiceSettings(context)
        settings.quickSettingsTile = true
        if (!label.isNullOrBlank()) settings.tileLabel = label
        SingBoxTileService.setEnabled(context, true)
        val statusBar = current.getSystemService(StatusBarManager::class.java)
        if (statusBar == null) {
            result.success("unsupported")
            return
        }
        val icon = Icon.createWithResource(context, AppInfo.iconResource(context, settings.notificationOptions.icon))
        try {
            statusBar.requestAddTileService(
                SingBoxTileService.component(context),
                settings.tileLabel ?: AppInfo.label(context),
                icon,
                ContextCompat.getMainExecutor(context),
            ) { code ->
                result.success(
                    when (code) {
                        StatusBarManager.TILE_ADD_REQUEST_RESULT_TILE_ADDED -> "added"
                        StatusBarManager.TILE_ADD_REQUEST_RESULT_TILE_ALREADY_ADDED -> "alreadyAdded"
                        StatusBarManager.TILE_ADD_REQUEST_RESULT_TILE_NOT_ADDED -> "declined"
                        else -> "unsupported"
                    },
                )
            }
        } catch (e: Exception) {
            Log.w(TAG, "requestAddTileService", e)
            result.success("unsupported")
        }
    }

    // ---------------------------------------------------------------------------------------
    // Service control
    // ---------------------------------------------------------------------------------------

    private suspend fun start(config: String, oomKiller: String, memoryLimit: Long) {
        checkConfig(config)
        if (!hasVpnPermission()) throw SingBoxError.permissionDenied()
        val settings = ServiceSettings(context)
        io {
            settings.oomKiller = oomKiller
            settings.memoryLimit = memoryLimit
            Paths.writeLastConfig(context, config)
        }
        val service = SingBoxVpnService.instance
        when (ServiceState.status) {
            ServiceStatus.Started, ServiceStatus.Starting -> {
                // Already running: reload with the new last config. A start that has not
                // reached the service yet reads the new config by itself.
                if (service == null && ServiceState.status == ServiceStatus.Starting) return
                (service ?: throw SingBoxError.notRunning()).reload()
                return
            }
            ServiceStatus.Stopping, ServiceStatus.Stopped -> Unit
        }
        val wasStopped = ServiceState.status == ServiceStatus.Stopped
        if (wasStopped) {
            // Report `connecting` before the method result (contract); the service
            // continues from this state.
            SingBoxVpnService.cancelPendingStop()
            ServiceState.update { it.copy(status = ServiceStatus.Starting, startedAt = null) }
        }
        try {
            SingBoxVpnService.start(context)
        } catch (e: Exception) {
            val message = "android: cannot start the VPN service: ${e.libboxMessage}"
            if (wasStopped) {
                ServiceState.update { it.copy(status = ServiceStatus.Stopped, startedAt = null, error = message) }
            }
            throw SingBoxError(SingBoxError.START_FAILED, message)
        }
    }

    private fun stop() {
        val service = SingBoxVpnService.instance
        if (service != null) {
            service.requestStop(userInitiated = true)
        } else if (ServiceState.status != ServiceStatus.Stopped) {
            // Started by us but the service has not been created yet.
            SingBoxVpnService.requestPendingStop(context)
        }
    }

    private suspend fun reload(config: String?) {
        if (!ServiceState.isRunning) throw SingBoxError.notRunning()
        if (config != null) {
            checkConfig(config)
            io { Paths.writeLastConfig(context, config) }
        }
        (SingBoxVpnService.instance ?: throw SingBoxError.notRunning()).reload()
    }

    private fun setServiceOptions(options: Map<*, *>) {
        val settings = ServiceSettings(context)
        (options["startOnBoot"] as? Boolean)?.let { settings.startOnBoot = it }
        (options["allowBypass"] as? Boolean)?.let { settings.allowBypass = it }
        (options["quickSettingsTile"] as? Boolean)?.let {
            settings.quickSettingsTile = it
            SingBoxTileService.setEnabled(context, it)
        }
    }

    // ---------------------------------------------------------------------------------------
    // Command client operations
    // ---------------------------------------------------------------------------------------

    private fun command(result: MethodChannel.Result, block: (CommandClient) -> Unit) =
        commandResult(result) {
            block(it)
            null
        }

    private fun commandResult(result: MethodChannel.Result, block: (CommandClient) -> Any?) = respond(result) {
        if (!ServiceState.isRunning) throw SingBoxError.notRunning()
        io {
            try {
                // Standalone clients close their connection after every call.
                block(Libbox.newStandaloneCommandClient())
            } catch (e: Exception) {
                throw SingBoxError(SingBoxError.COMMAND_FAILED, e.libboxMessage)
            }
        }
    }

    private companion object {
        const val TAG = "sing_box"
        const val REQUEST_VPN = 0x5B01
        const val REQUEST_NOTIFICATIONS = 0x5B02
    }
}
