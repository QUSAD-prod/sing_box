package com.qusadprod.sing_box

import android.app.Activity
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.VpnService
import android.os.Bundle
import androidx.core.content.ContextCompat
import com.qusadprod.sing_box.bg.SingBoxVPNService
import com.qusadprod.sing_box.constant.Action
import com.qusadprod.sing_box.constant.Status
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import java.util.concurrent.atomic.AtomicReference
import com.google.gson.Gson
import com.google.gson.JsonObject

/** SingBoxPlugin */
class SingBoxPlugin : FlutterPlugin, MethodCallHandler, ActivityAware {
    // The MethodChannel that will the communication between Flutter and native Android
    private lateinit var channel: MethodChannel
    
    // Event channels for status and stats streams
    private lateinit var statusEventChannel: EventChannel
    private lateinit var statsEventChannel: EventChannel
    private lateinit var notificationsEventChannel: EventChannel
    
    private var activity: Activity? = null
    private var context: Context? = null
    
    // Coroutine scope for async operations
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    
    // VPN Service class
    private val vpnServiceClass = SingBoxVPNService::class.java
    
    // Bypass Manager для управления bypass списками
    private var bypassManager: BypassManager? = null
    
    // DNS Manager для управления DNS серверами
    private var dnsManager: DnsManager? = null
    
    // Settings Manager для управления настройками
    private var settingsManager: SettingsManager? = null
    
    // Server Config Manager для управления конфигурациями серверов
    private var serverConfigManager: ServerConfigManager? = null
    
    // Block Manager для управления блокировкой приложений и доменов
    private var blockManager: BlockManager? = null
    
    // Текущий статус соединения (кэшируется из Broadcast)
    private val currentStatus = AtomicReference<String>("disconnected")
    
    companion object {
        // Константы для ожидания отключения VPN
        private const val DISCONNECT_WAIT_MAX_ATTEMPTS = 50
        private const val DISCONNECT_WAIT_DELAY_MS = 100L
    }
    
    // Последняя статистика соединения (кэшируется из Broadcast)
    private val lastStats = AtomicReference<Map<String, Any?>>(
        mapOf(
            "downloadSpeed" to 0L,
            "uploadSpeed" to 0L,
            "bytesSent" to 0L,
            "bytesReceived" to 0L,
            "ping" to null,
            "connectionDuration" to 0L
        )
    )
    
    // Stream handlers для Event Channels
    private var statusStreamHandler: StatusStreamHandler? = null
    private var statsStreamHandler: StatsStreamHandler? = null
    private var notificationsStreamHandler: NotificationsStreamHandler? = null
    
    // BroadcastReceiver для получения статуса и статистики
    private val statusReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            when (intent?.action) {
                Action.STATUS_UPDATE -> {
                    val status = intent.getStringExtra(Action.EXTRA_STATUS) ?: "disconnected"
                    currentStatus.set(status)
                    statusStreamHandler?.sendStatus(status)
                }
                Action.STATS_UPDATE -> {
                    val statsBundle = intent.getBundleExtra(Action.EXTRA_STATS)
                    if (statsBundle != null) {
                        val stats = bundleToMap(statsBundle)
                        // Кэшируем последнюю статистику
                        lastStats.set(stats)
                        // Отправляем в Event Channel
                        statsStreamHandler?.sendStats(stats)
                    }
                }
                Action.NOTIFICATION_UPDATE -> {
                    val notification = mapOf(
                        "identifier" to (intent.getStringExtra(Action.EXTRA_NOTIFICATION_IDENTIFIER) ?: ""),
                        "typeName" to (intent.getStringExtra(Action.EXTRA_NOTIFICATION_TYPE_NAME) ?: ""),
                        "typeId" to (intent.getIntExtra(Action.EXTRA_NOTIFICATION_TYPE_ID, 0)),
                        "title" to (intent.getStringExtra(Action.EXTRA_NOTIFICATION_TITLE) ?: ""),
                        "subtitle" to (intent.getStringExtra(Action.EXTRA_NOTIFICATION_SUBTITLE) ?: ""),
                        "body" to (intent.getStringExtra(Action.EXTRA_NOTIFICATION_BODY) ?: ""),
                        "openUrl" to intent.getStringExtra(Action.EXTRA_NOTIFICATION_OPEN_URL)
                    )
                    notificationsStreamHandler?.sendNotification(notification)
                }
            }
        }
    }
    
    private fun bundleToMap(bundle: Bundle): Map<String, Any?> {
        val map = mutableMapOf<String, Any?>()
        for (key in bundle.keySet()) {
            val value = bundle.get(key)
            when (value) {
                is Long -> map[key] = value
                is Int -> map[key] = value.toLong()
                is String -> map[key] = value
                is Boolean -> map[key] = value
                null -> map[key] = null
                else -> map[key] = value.toString()
            }
        }
        // Убеждаемся, что ping присутствует (может быть null)
        if (!map.containsKey("ping")) {
            map["ping"] = null
        }
        return map
    }

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        context = flutterPluginBinding.applicationContext
        context?.let { ctx ->
            bypassManager = BypassManager(ctx)
            dnsManager = DnsManager(ctx)
            settingsManager = SettingsManager(ctx)
            serverConfigManager = ServerConfigManager(ctx)
            blockManager = BlockManager(ctx)
        }
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "sing_box")
        channel.setMethodCallHandler(this)
        
        // Настройка Event Channels
        statusEventChannel = EventChannel(flutterPluginBinding.binaryMessenger, "sing_box/status")
        statusStreamHandler = StatusStreamHandler()
        statusEventChannel.setStreamHandler(statusStreamHandler)
        
        statsEventChannel = EventChannel(flutterPluginBinding.binaryMessenger, "sing_box/stats")
        statsStreamHandler = StatsStreamHandler()
        statsEventChannel.setStreamHandler(statsStreamHandler)
        
        // Настройка Event Channel для уведомлений
        notificationsEventChannel = EventChannel(flutterPluginBinding.binaryMessenger, "sing_box/notifications")
        notificationsStreamHandler = NotificationsStreamHandler()
        notificationsEventChannel.setStreamHandler(notificationsStreamHandler)
        
        // Регистрация BroadcastReceiver
        val filter = IntentFilter().apply {
            addAction(Action.STATUS_UPDATE)
            addAction(Action.STATS_UPDATE)
            addAction(Action.NOTIFICATION_UPDATE)
        }
        // Используем RECEIVER_NOT_EXPORTED для безопасности (Android 8.0+)
        context?.let { ctx ->
            ContextCompat.registerReceiver(ctx, statusReceiver, filter, ContextCompat.RECEIVER_NOT_EXPORTED)
        }
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "initialize" -> {
                // Инициализация уже выполнена при создании компонентов
                // Все компоненты создаются в SingBoxVPNService.onCreate()
                result.success(true)
            }
            "getPlatformVersion" -> {
                result.success("Android ${android.os.Build.VERSION.RELEASE}")
            }
            "connect" -> {
                val config = call.argument<String>("config")
                if (config == null || config.isBlank()) {
                    result.error("INVALID_ARGUMENT", "Config is required and cannot be empty", null)
                    return
                }
                
                val activity = activity
                if (activity == null) {
                    result.error("NO_ACTIVITY", "Activity is not available", null)
                    return
                }
                
                // Запрос разрешения VPN
                val vpnIntent = VpnService.prepare(activity)
                if (vpnIntent != null) {
                    // Нужно запросить разрешение
                    result.error("VPN_PERMISSION_REQUIRED", "VPN permission is required", null)
                    return
                }
                
                // Запуск VPN сервиса
                scope.launch {
                    try {
                        val intent = Intent(context, vpnServiceClass).apply {
                            action = SingBoxVPNService.ACTION_START
                            putExtra(SingBoxVPNService.EXTRA_CONFIG, config)
                            putExtra(SingBoxVPNService.EXTRA_DISABLE_MEMORY_LIMIT, false)
                        }
                        // Сохраняем конфигурацию в кэш для получения адреса сервера
                        currentConfigCache.set(config)
                        context?.let { ctx ->
                            ContextCompat.startForegroundService(ctx, intent)
                            result.success(true)
                        } ?: run {
                            result.error("CONTEXT_NULL", "Context is null, cannot start service", null)
                        }
                    } catch (e: Exception) {
                        result.error("CONNECTION_FAILED", "Failed to start VPN service: ${e.message}", null)
                    }
                }
            }
            "disconnect" -> {
                scope.launch {
                    try {
                        val intent = Intent(context, vpnServiceClass).apply {
                            action = SingBoxVPNService.ACTION_STOP
                        }
                        context?.startService(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("DISCONNECTION_FAILED", "Failed to stop VPN service: ${e.message}", null)
                    }
                }
            }
            "getConnectionStatus" -> {
                // Получаем статус из кэша (обновляется через BroadcastReceiver)
                result.success(currentStatus.get())
            }
            "getConnectionStats" -> {
                // Возвращаем последнюю статистику из кэша
                // Статистика обновляется каждую секунду через BroadcastReceiver
                val stats = lastStats.get()
                result.success(stats)
            }
            "testSpeed" -> {
                // Тест скорости использует текущую статистику соединения
                scope.launch {
                    try {
                        val stats = lastStats.get()
                        val downloadSpeed = stats["downloadSpeed"] as? Long ?: 0L
                        val uploadSpeed = stats["uploadSpeed"] as? Long ?: 0L
                        val isConnected = currentStatus.get() == "connected"
                        
                        result.success(mapOf(
                            "downloadSpeed" to downloadSpeed,
                            "uploadSpeed" to uploadSpeed,
                            "success" to isConnected,
                            "errorMessage" to if (isConnected) null else "Not connected to VPN"
                        ))
                    } catch (e: Exception) {
                        result.success(mapOf(
                            "downloadSpeed" to 0,
                            "uploadSpeed" to 0,
                            "success" to false,
                            "errorMessage" to e.message ?: "Unknown error"
                        ))
                    }
                }
            }
            "pingCurrentServer" -> {
                // Ping использует текущую статистику соединения
                scope.launch {
                    try {
                        val stats = lastStats.get()
                        val ping = stats["ping"] as? Long
                        val isConnected = currentStatus.get() == "connected"
                        
                        result.success(mapOf(
                            "ping" to (ping ?: 0),
                            "success" to (isConnected && ping != null && ping > 0),
                            "errorMessage" to if (!isConnected) "Not connected to VPN" else if (ping == null) "Ping not available" else null,
                            "address" to getCurrentServerAddress()
                        ))
                    } catch (e: Exception) {
                        result.success(mapOf(
                            "ping" to 0,
                            "success" to false,
                            "errorMessage" to e.message ?: "Unknown error",
                            "address" to null
                        ))
                    }
                }
            }
            "addAppToBypass" -> {
                val packageName = call.argument<String>("packageName")
                if (packageName == null || packageName.isBlank()) {
                    result.error("INVALID_ARGUMENT", "Package name is required", null)
                    return
                }
                val success = bypassManager?.addAppToBypass(packageName) ?: false
                if (success && currentStatus.get() == "connected") {
                    // Перезапустить VPN для применения изменений
                    val reloadIntent = Intent(context, vpnServiceClass).apply {
                        action = SingBoxVPNService.ACTION_RELOAD
                    }
                    context?.startService(reloadIntent)
                }
                result.success(success)
            }
            "removeAppFromBypass" -> {
                val packageName = call.argument<String>("packageName")
                if (packageName == null || packageName.isBlank()) {
                    result.error("INVALID_ARGUMENT", "Package name is required", null)
                    return
                }
                val success = bypassManager?.removeAppFromBypass(packageName) ?: false
                if (success && currentStatus.get() == "connected") {
                    // Перезапустить VPN для применения изменений
                    val reloadIntent = Intent(context, vpnServiceClass).apply {
                        action = SingBoxVPNService.ACTION_RELOAD
                    }
                    context?.startService(reloadIntent)
                }
                result.success(success)
            }
            "getBypassApps" -> {
                val apps = bypassManager?.getBypassApps() ?: emptyList()
                result.success(apps)
            }
            "addDomainToBypass" -> {
                val domain = call.argument<String>("domain")
                if (domain == null || domain.isBlank()) {
                    result.error("INVALID_ARGUMENT", "Domain is required", null)
                    return
                }
                val success = bypassManager?.addDomainToBypass(domain) ?: false
                result.success(success)
            }
            "removeDomainFromBypass" -> {
                val domain = call.argument<String>("domain")
                if (domain == null || domain.isBlank()) {
                    result.error("INVALID_ARGUMENT", "Domain is required", null)
                    return
                }
                val success = bypassManager?.removeDomainFromBypass(domain) ?: false
                result.success(success)
            }
            "getBypassDomains" -> {
                val domains = bypassManager?.getBypassDomains() ?: emptyList()
                result.success(domains)
            }
            "switchServer" -> {
                val config = call.argument<String>("config")
                if (config == null || config.isBlank()) {
                    result.error("INVALID_ARGUMENT", "Config is required and cannot be empty", null)
                    return
                }
                
                scope.launch {
                    try {
                        val currentStatusValue = currentStatus.get()
                        
                        // Если VPN не подключен, просто подключаемся с новой конфигурацией
                        if (currentStatusValue != "connected" && currentStatusValue != "connecting") {
                            // Прямое подключение с новой конфигурацией
                            val activity = activity
                            if (activity == null) {
                                result.error("NO_ACTIVITY", "Activity is not available", null)
                                return@launch
                            }
                            
                            val vpnIntent = VpnService.prepare(activity)
                            if (vpnIntent != null) {
                                result.error("VPN_PERMISSION_REQUIRED", "VPN permission is required", null)
                                return@launch
                            }
                            
                        val intent = Intent(context, vpnServiceClass).apply {
                            action = SingBoxVPNService.ACTION_START
                            putExtra(SingBoxVPNService.EXTRA_CONFIG, config)
                            putExtra(SingBoxVPNService.EXTRA_DISABLE_MEMORY_LIMIT, false)
                        }
                        // Сохраняем конфигурацию в кэш для получения адреса сервера
                        currentConfigCache.set(config)
                        context?.let { ctx ->
                            ContextCompat.startForegroundService(ctx, intent)
                            result.success(true)
                        } ?: run {
                            result.error("CONTEXT_NULL", "Context is null, cannot start service", null)
                        }
                            return@launch
                        }
                        
                        // Если VPN подключен, сначала отключаемся
                        val disconnectIntent = Intent(context, vpnServiceClass).apply {
                            action = SingBoxVPNService.ACTION_STOP
                        }
                        context?.startService(disconnectIntent)
                        
                        // Ждем отключения (максимум 5 секунд)
                        var attempts = 0
                        while (attempts < DISCONNECT_WAIT_MAX_ATTEMPTS && currentStatus.get() != "disconnected") {
                            delay(DISCONNECT_WAIT_DELAY_MS)
                            attempts++
                        }
                        
                        // Проверяем, что отключились
                        if (currentStatus.get() != "disconnected") {
                            result.error("DISCONNECT_TIMEOUT", "Failed to disconnect from current server", null)
                            return@launch
                        }
                        
                        // Небольшая задержка перед переподключением
                        delay(500)
                        
                        // Подключаемся с новой конфигурацией
                        val activity = activity
                        if (activity == null) {
                            result.error("NO_ACTIVITY", "Activity is not available", null)
                            return@launch
                        }
                        
                        val vpnIntent = VpnService.prepare(activity)
                        if (vpnIntent != null) {
                            result.error("VPN_PERMISSION_REQUIRED", "VPN permission is required", null)
                            return@launch
                        }
                        
                        val connectIntent = Intent(context, vpnServiceClass).apply {
                            action = SingBoxVPNService.ACTION_START
                            putExtra(SingBoxVPNService.EXTRA_CONFIG, config)
                            putExtra(SingBoxVPNService.EXTRA_DISABLE_MEMORY_LIMIT, false)
                        }
                        // Сохраняем конфигурацию в кэш для получения адреса сервера
                        currentConfigCache.set(config)
                        context?.let { ctx ->
                            ContextCompat.startForegroundService(ctx, connectIntent)
                            result.success(true)
                        } ?: run {
                            result.error("CONTEXT_NULL", "Context is null, cannot start service", null)
                        }
                    } catch (e: Exception) {
                        result.error("SWITCH_SERVER_FAILED", "Failed to switch server: ${e.message}", null)
                    }
                }
            }
            "saveSettings" -> {
                val settings = call.argument<Map<String, Any>>("settings")
                if (settings == null) {
                    result.error("INVALID_ARGUMENT", "Settings map is required", null)
                    return
                }
                val success = settingsManager?.saveSettings(settings) ?: false
                result.success(success)
            }
            "loadSettings" -> {
                val settings = settingsManager?.loadSettings() ?: mapOf<String, Any>()
                result.success(settings)
            }
            "getSettings" -> {
                val settings = settingsManager?.getSettings() ?: mapOf<String, Any>()
                result.success(settings)
            }
            "updateSetting" -> {
                val key = call.argument<String>("key")
                val value = call.arguments["value"]
                if (key == null || key.isBlank()) {
                    result.error("INVALID_ARGUMENT", "Setting key is required", null)
                    return
                }
                val success = settingsManager?.updateSetting(key, value) ?: false
                result.success(success)
            }
            "addServerConfig" -> {
                val config = call.argument<Map<String, Any>>("config")
                if (config == null) {
                    result.error("INVALID_ARGUMENT", "Config is required", null)
                    return
                }
                val configId = config["id"] as? String
                if (configId.isNullOrBlank()) {
                    result.error("INVALID_ARGUMENT", "Config ID is required", null)
                    return
                }
                val success = serverConfigManager?.addServerConfig(config) ?: false
                result.success(success)
            }
            "removeServerConfig" -> {
                val configId = call.argument<String>("configId")
                if (configId == null || configId.isBlank()) {
                    result.error("INVALID_ARGUMENT", "Config ID is required", null)
                    return
                }
                val success = serverConfigManager?.removeServerConfig(configId) ?: false
                result.success(success)
            }
            "updateServerConfig" -> {
                val config = call.argument<Map<String, Any>>("config")
                if (config == null) {
                    result.error("INVALID_ARGUMENT", "Config is required", null)
                    return
                }
                val configId = config["id"] as? String
                if (configId.isNullOrBlank()) {
                    result.error("INVALID_ARGUMENT", "Config ID is required", null)
                    return
                }
                val success = serverConfigManager?.updateServerConfig(config) ?: false
                result.success(success)
            }
            "getServerConfigs" -> {
                val configs = serverConfigManager?.getServerConfigs() ?: emptyList()
                result.success(configs)
            }
            "getServerConfig" -> {
                val configId = call.argument<String>("configId")
                if (configId == null || configId.isBlank()) {
                    result.error("INVALID_ARGUMENT", "Config ID is required", null)
                    return
                }
                val config = serverConfigManager?.getServerConfig(configId)
                result.success(config)
            }
            "setActiveServerConfig" -> {
                val configId = call.argument<String>("configId")
                // configId может быть null для сброса активной конфигурации
                val success = serverConfigManager?.setActiveServerConfig(configId) ?: false
                result.success(success)
            }
            "getActiveServerConfig" -> {
                val config = serverConfigManager?.getActiveServerConfig()
                result.success(config)
            }
            "addBlockedApp" -> {
                val packageName = call.argument<String>("packageName")
                if (packageName == null || packageName.isBlank()) {
                    result.error("INVALID_ARGUMENT", "Package name is required", null)
                    return
                }
                val success = blockManager?.addBlockedApp(packageName) ?: false
                if (success && currentStatus.get() == "connected") {
                    // Перезапустить VPN для применения изменений блокировки
                    val reloadIntent = Intent(context, vpnServiceClass).apply {
                        action = SingBoxVPNService.ACTION_RELOAD
                    }
                    context?.startService(reloadIntent)
                }
                result.success(success)
            }
            "removeBlockedApp" -> {
                val packageName = call.argument<String>("packageName")
                if (packageName == null || packageName.isBlank()) {
                    result.error("INVALID_ARGUMENT", "Package name is required", null)
                    return
                }
                val success = blockManager?.removeBlockedApp(packageName) ?: false
                if (success && currentStatus.get() == "connected") {
                    // Перезапустить VPN для применения изменений блокировки
                    val reloadIntent = Intent(context, vpnServiceClass).apply {
                        action = SingBoxVPNService.ACTION_RELOAD
                    }
                    context?.startService(reloadIntent)
                }
                result.success(success)
            }
            "getBlockedApps" -> {
                val apps = blockManager?.getBlockedApps() ?: emptyList()
                result.success(apps)
            }
            "addBlockedDomain" -> {
                val domain = call.argument<String>("domain")
                if (domain == null || domain.isBlank()) {
                    result.error("INVALID_ARGUMENT", "Domain is required", null)
                    return
                }
                val success = blockManager?.addBlockedDomain(domain) ?: false
                if (success && currentStatus.get() == "connected") {
                    // Перезапустить VPN для применения изменений блокировки
                    val reloadIntent = Intent(context, vpnServiceClass).apply {
                        action = SingBoxVPNService.ACTION_RELOAD
                    }
                    context?.startService(reloadIntent)
                }
                result.success(success)
            }
            "removeBlockedDomain" -> {
                val domain = call.argument<String>("domain")
                if (domain == null || domain.isBlank()) {
                    result.error("INVALID_ARGUMENT", "Domain is required", null)
                    return
                }
                val success = blockManager?.removeBlockedDomain(domain) ?: false
                if (success && currentStatus.get() == "connected") {
                    // Перезапустить VPN для применения изменений блокировки
                    val reloadIntent = Intent(context, vpnServiceClass).apply {
                        action = SingBoxVPNService.ACTION_RELOAD
                    }
                    context?.startService(reloadIntent)
                }
                result.success(success)
            }
            "getBlockedDomains" -> {
                val domains = blockManager?.getBlockedDomains() ?: emptyList()
                result.success(domains)
            }
            "addSubnetToBypass" -> {
                val subnet = call.argument<String>("subnet")
                if (subnet == null || subnet.isBlank()) {
                    result.error("INVALID_ARGUMENT", "Subnet is required", null)
                    return
                }
                val success = bypassManager?.addSubnetToBypass(subnet) ?: false
                if (!success) {
                    result.error("INVALID_SUBNET", "Invalid subnet format. Expected CIDR notation (e.g., 192.168.1.0/24)", null)
                    return
                }
                if (success && currentStatus.get() == "connected") {
                    // Перезапустить VPN для применения изменений
                    val reloadIntent = Intent(context, vpnServiceClass).apply {
                        action = SingBoxVPNService.ACTION_RELOAD
                    }
                    context?.startService(reloadIntent)
                }
                result.success(true)
            }
            "removeSubnetFromBypass" -> {
                val subnet = call.argument<String>("subnet")
                if (subnet == null || subnet.isBlank()) {
                    result.error("INVALID_ARGUMENT", "Subnet is required", null)
                    return
                }
                val success = bypassManager?.removeSubnetFromBypass(subnet) ?: false
                if (success && currentStatus.get() == "connected") {
                    // Перезапустить VPN для применения изменений
                    val reloadIntent = Intent(context, vpnServiceClass).apply {
                        action = SingBoxVPNService.ACTION_RELOAD
                    }
                    context?.startService(reloadIntent)
                }
                result.success(success)
            }
            "getBypassSubnets" -> {
                val subnets = bypassManager?.getBypassSubnets() ?: emptyList()
                result.success(subnets)
            }
            "addDnsServer" -> {
                val dnsServer = call.argument<String>("dnsServer")
                if (dnsServer == null || dnsServer.isBlank()) {
                    result.error("INVALID_ARGUMENT", "DNS server is required", null)
                    return
                }
                val success = dnsManager?.addDnsServer(dnsServer) ?: false
                if (!success) {
                    result.error("INVALID_DNS", "Invalid DNS server format. Expected IPv4 or IPv6 address (e.g., 8.8.8.8)", null)
                    return
                }
                if (success && currentStatus.get() == "connected") {
                    // Перезапустить VPN для применения изменений DNS
                    val reloadIntent = Intent(context, vpnServiceClass).apply {
                        action = SingBoxVPNService.ACTION_RELOAD
                    }
                    context?.startService(reloadIntent)
                }
                result.success(true)
            }
            "removeDnsServer" -> {
                val dnsServer = call.argument<String>("dnsServer")
                if (dnsServer == null || dnsServer.isBlank()) {
                    result.error("INVALID_ARGUMENT", "DNS server is required", null)
                    return
                }
                val success = dnsManager?.removeDnsServer(dnsServer) ?: false
                if (success && currentStatus.get() == "connected") {
                    // Перезапустить VPN для применения изменений DNS
                    val reloadIntent = Intent(context, vpnServiceClass).apply {
                        action = SingBoxVPNService.ACTION_RELOAD
                    }
                    context?.startService(reloadIntent)
                }
                result.success(success)
            }
            "getDnsServers" -> {
                val servers = dnsManager?.getDnsServers() ?: emptyList()
                result.success(servers)
            }
            "setDnsServers" -> {
                val dnsServers = call.argument<List<String>>("dnsServers")
                if (dnsServers == null) {
                    result.error("INVALID_ARGUMENT", "DNS servers list is required", null)
                    return
                }
                val success = dnsManager?.setDnsServers(dnsServers) ?: false
                if (!success) {
                    result.error("INVALID_DNS", "One or more DNS servers have invalid format", null)
                    return
                }
                if (success && currentStatus.get() == "connected") {
                    // Перезапустить VPN для применения изменений DNS
                    val reloadIntent = Intent(context, vpnServiceClass).apply {
                        action = SingBoxVPNService.ACTION_RELOAD
                    }
                    context?.startService(reloadIntent)
                }
                result.success(true)
            }
            else -> {
                result.notImplemented()
            }
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        
        // Отмена регистрации Event Channels
        statusEventChannel.setStreamHandler(null)
        statsEventChannel.setStreamHandler(null)
        notificationsEventChannel.setStreamHandler(null)
        statusStreamHandler = null
        statsStreamHandler = null
        
        // Отмена регистрации BroadcastReceiver
        try {
            context?.unregisterReceiver(statusReceiver)
        } catch (e: Exception) {
            // Игнорируем ошибки при отмене регистрации, но логируем для отладки
            android.util.Log.w("SingBoxPlugin", "Error unregistering receiver", e)
        }
        
        context = null
    }
    
    /**
     * Получить адрес сервера из текущей конфигурации
     * Парсит JSON конфигурацию и извлекает адрес сервера
     */
    private fun getCurrentServerAddress(): String? {
        val config = currentConfigCache.get() ?: return null
        return try {
            // Парсим JSON конфигурацию
            val jsonObject = Gson().fromJson(config, JsonObject::class.java)
            
            // Валидация структуры JSON
            if (!jsonObject.has("outbounds")) {
                return null
            }
            
            // Ищем outbounds
            val outbounds = jsonObject.getAsJsonArray("outbounds")
            if (outbounds == null || outbounds.size() == 0) {
                return null
            }
            
            // Берем первый outbound (обычно это основной сервер)
            val firstOutbound = outbounds.get(0).asJsonObject
            
            // Пробуем получить адрес из разных полей в зависимости от протокола
            // Для большинства протоколов адрес находится в поле "server"
            val serverField = firstOutbound.get("server")
            if (serverField != null && serverField.isJsonPrimitive) {
                val serverValue = serverField.asString
                if (serverValue.isNotEmpty()) {
                    return serverValue
                }
            }
            
            // Для некоторых протоколов адрес может быть в "settings.server"
            val settings = firstOutbound.getAsJsonObject("settings")
            if (settings != null) {
                val serverInSettings = settings.get("server")
                if (serverInSettings != null && serverInSettings.isJsonPrimitive) {
                    val serverValue = serverInSettings.asString
                    if (serverValue.isNotEmpty()) {
                        return serverValue
                    }
                }
                
                // Для shadowsocks адрес может быть в "settings.address"
                val address = settings.get("address")
                if (address != null && address.isJsonPrimitive) {
                    val addressValue = address.asString
                    if (addressValue.isNotEmpty()) {
                        return addressValue
                    }
                }
            }
            
            null
        } catch (e: Exception) {
            null
        }
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivity() {
        activity = null
    }
    
    /**
     * StreamHandler для статуса соединения
     */
    private class StatusStreamHandler : EventChannel.StreamHandler {
        private var eventSink: EventChannel.EventSink? = null
        
        override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
            eventSink = events
        }
        
        override fun onCancel(arguments: Any?) {
            eventSink = null
        }
        
        fun sendStatus(status: String) {
            eventSink?.success(status)
        }
    }
    
    /**
     * StreamHandler для статистики соединения
     */
    private class StatsStreamHandler : EventChannel.StreamHandler {
        private var eventSink: EventChannel.EventSink? = null
        
        override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
            eventSink = events
        }
        
        override fun onCancel(arguments: Any?) {
            eventSink = null
        }
        
        fun sendStats(stats: Map<String, Any>) {
            eventSink?.success(stats)
        }
    }
    
    private class NotificationsStreamHandler : EventChannel.StreamHandler {
        private var eventSink: EventChannel.EventSink? = null

        override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
            eventSink = events
        }

        override fun onCancel(arguments: Any?) {
            eventSink = null
        }

        fun sendNotification(notification: Map<String, Any?>) {
            eventSink?.success(notification)
        }
    }
}
