package com.qusadprod.sing_box.bg

import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.IBinder
import android.os.ParcelFileDescriptor
import android.os.PowerManager
import androidx.annotation.RequiresApi
import androidx.core.content.ContextCompat
import androidx.lifecycle.MutableLiveData
import go.Seq
import io.nekohasekai.libbox.BoxService
import io.nekohasekai.libbox.CommandServer
import io.nekohasekai.libbox.CommandServerHandler
import io.nekohasekai.libbox.Libbox
import io.nekohasekai.libbox.Notification
import io.nekohasekai.libbox.PlatformInterface
import io.nekohasekai.libbox.SystemProxyStatus
import com.qusadprod.sing_box.constant.Action
import com.qusadprod.sing_box.constant.Alert
import com.qusadprod.sing_box.constant.Status
import androidx.lifecycle.Observer
import com.qusadprod.sing_box.ktx.hasPermission
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import android.util.Log

/**
 * Основной сервис для управления sing-box
 * Скопировано и адаптировано из sing-box-for-android
 * Адаптировано для работы с конфигурацией из Method Channel вместо файлов
 */
class SingBoxService(
    private val service: Service,
    private val context: Context,
    private val platformInterface: PlatformInterface,
    private val networkMonitor: DefaultNetworkMonitor
) : CommandServerHandler {

    companion object {
        // Константы для интервалов и задержек
        private const val STATS_BROADCAST_INTERVAL_MS = 1000L
    }

    var fileDescriptor: ParcelFileDescriptor? = null

    private val status = MutableLiveData(Status.Stopped)
    private var boxService: io.nekohasekai.libbox.BoxService? = null
    private var commandServer: CommandServer? = null
    private var receiverRegistered = false
    private var currentConfig: String? = null
    private var disableMemoryLimit: Boolean = false
    private var statsJob: Job? = null
    
    // CoroutineScope с SupervisorJob для управления жизненным циклом корутин
    private val serviceScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    
    // Для вычисления скорости - храним предыдущие значения и время
    private var previousBytesSent: Long = 0
    private var previousBytesReceived: Long = 0
    private var previousStatsTime: Long = 0
    
    // Время начала соединения для вычисления duration
    private var connectionStartTime: Long = 0
    
    // Observer для отправки Broadcast при изменении статуса
    private val statusObserver = Observer<Status> { newStatus ->
        sendStatusBroadcast(newStatus)
        // Запускаем или останавливаем периодическую отправку статистики
        if (newStatus == Status.Started) {
            startStatsBroadcast()
        } else {
            stopStatsBroadcast()
        }
    }
    
    init {
        // Подписываемся на изменения статуса
        status.observeForever(statusObserver)
    }
    
    /**
     * Отменяет подписку на изменения статуса для предотвращения утечек памяти
     */
    private fun removeStatusObserver() {
        status.removeObserver(statusObserver)
    }

    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            when (intent.action) {
                Action.SERVICE_CLOSE -> {
                    stopService()
                }

                PowerManager.ACTION_DEVICE_IDLE_MODE_CHANGED -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        serviceUpdateIdleMode()
                    }
                }
            }
        }
    }

    private fun startCommandServer() {
        val commandServer = CommandServer(this, 300)
        commandServer.start()
        this.commandServer = commandServer
    }

    suspend fun startService(config: String, disableMemoryLimit: Boolean = false) {
        try {
            this.currentConfig = config
            this.disableMemoryLimit = disableMemoryLimit

            if (config.isBlank()) {
                stopAndAlert(Alert.EmptyConfiguration)
                return
            }

            networkMonitor.start()
            Libbox.setMemoryLimit(!disableMemoryLimit)

            val newService = try {
                Libbox.newService(config, platformInterface)
            } catch (e: Exception) {
                Log.e("SingBoxService", "Error creating new service", e)
                stopAndAlert(Alert.CreateService, e.message)
                return
            }

            newService.start()

            if (newService.needWIFIState()) {
                val wifiPermission = if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
                    android.Manifest.permission.ACCESS_FINE_LOCATION
                } else {
                    android.Manifest.permission.ACCESS_BACKGROUND_LOCATION
                }
                if (!service.hasPermission(wifiPermission)) {
                    newService.close()
                    stopAndAlert(Alert.RequestLocationPermission)
                    return
                }
            }

            boxService = newService
            commandServer?.setService(boxService)
            status.postValue(Status.Started)
            
            // Запоминаем время начала соединения
            connectionStartTime = System.currentTimeMillis()
            previousStatsTime = connectionStartTime
            previousBytesSent = 0
            previousBytesReceived = 0
        } catch (e: Exception) {
            Log.e("SingBoxService", "Error starting service", e)
            stopAndAlert(Alert.StartService, e.message)
            return
        }
    }

    override fun serviceReload() {
        status.postValue(Status.Starting)
        // Безопасное закрытие fileDescriptor с использованием use
        fileDescriptor?.use { }
        fileDescriptor = null
        boxService?.apply {
            runCatching {
                close()
            }.onFailure {
                writeLog("service: error when closing: $it")
            }
            Seq.destroyRef(refnum)
        }
        commandServer?.setService(null)
        commandServer?.resetLog()
        boxService = null
        val config = currentConfig
        if (config != null) {
            // Используем CoroutineScope вместо runBlocking
            serviceScope.launch(Dispatchers.IO) {
                startService(config, disableMemoryLimit)
            }
        }
    }

    override fun postServiceClose() {
        // Not used on Android
    }

    override fun getSystemProxyStatus(): SystemProxyStatus {
        val status = SystemProxyStatus()
        
            // Проверяем доступность системного прокси (только для Android Q+)
            status.available = Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q

            if (status.available) {
                // Проверяем, включен ли системный прокси
                // В Android системный прокси настраивается для Wi-Fi сетей
                try {
                    val connectivityManager = context.getSystemService(Context.CONNECTIVITY_SERVICE) as? android.net.ConnectivityManager
                    if (connectivityManager == null) {
                        status.enabled = false
                        return status
                    }
                    val activeNetwork = connectivityManager.activeNetwork
                
                if (activeNetwork != null) {
                    val linkProperties = connectivityManager.getLinkProperties(activeNetwork)
                    if (linkProperties != null) {
                        val proxyInfo = linkProperties.httpProxy
                        // Если proxyInfo не null и не DIRECT, значит прокси настроен
                        status.enabled = proxyInfo != null && proxyInfo != android.net.ProxyInfo.buildDirectProxy(null, 0)
                    } else {
                        status.enabled = false
                    }
                } else {
                    status.enabled = false
                }
            } catch (e: Exception) {
                // В случае ошибки считаем, что прокси отключен
                status.enabled = false
            }
        } else {
            status.enabled = false
        }
        
        return status
    }

    override fun setSystemProxyEnabled(isEnabled: Boolean) {
        serviceReload()
    }

    @RequiresApi(Build.VERSION_CODES.M)
    private fun serviceUpdateIdleMode() {
        val powerManager = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
        if (powerManager == null) {
            Log.w("SingBoxService", "PowerManager service is not available")
            return
        }
        if (powerManager.isDeviceIdleMode) {
            boxService?.pause()
        } else {
            boxService?.wake()
        }
    }

    @OptIn(DelicateCoroutinesApi::class)
    fun stopService() {
        if (status.value != Status.Started) return
        status.value = Status.Stopping
        
        // Сбрасываем время начала соединения
        connectionStartTime = 0
        previousStatsTime = 0
        previousBytesSent = 0
        previousBytesReceived = 0
        if (receiverRegistered) {
            service.unregisterReceiver(receiver)
            receiverRegistered = false
        }
        serviceScope.launch(Dispatchers.IO) {
            // Безопасное закрытие fileDescriptor с использованием use
            fileDescriptor?.use { }
            fileDescriptor = null
            boxService?.apply {
                runCatching {
                    close()
                }.onFailure { e ->
                    Log.e("SingBoxService", "Error closing boxService", e)
                    writeLog("service: error when closing: $it")
                }
                Seq.destroyRef(refnum)
            }
            commandServer?.setService(null)
            boxService = null
            networkMonitor.stop()

            commandServer?.apply {
                close()
                Seq.destroyRef(refnum)
            }
            commandServer = null
            withContext(Dispatchers.Main) {
                status.value = Status.Stopped
                service.stopSelf()
            }
        }
    }

    private suspend fun stopAndAlert(type: Alert, message: String? = null) {
        withContext(Dispatchers.Main) {
            if (receiverRegistered) {
                service.unregisterReceiver(receiver)
                receiverRegistered = false
            }
            status.value = Status.Stopped
        }
    }

    @OptIn(DelicateCoroutinesApi::class)
    fun onStartCommand(config: String?, disableMemoryLimit: Boolean = false): Int {
        if (status.value != Status.Stopped) return Service.START_NOT_STICKY
        status.value = Status.Starting

        if (!receiverRegistered) {
            ContextCompat.registerReceiver(service, receiver, IntentFilter().apply {
                addAction(Action.SERVICE_CLOSE)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    addAction(PowerManager.ACTION_DEVICE_IDLE_MODE_CHANGED)
                }
            }, ContextCompat.RECEIVER_NOT_EXPORTED)
            receiverRegistered = true
        }

        serviceScope.launch(Dispatchers.IO) {
            try {
                startCommandServer()
            } catch (e: Exception) {
                Log.e("SingBoxService", "Error starting command server", e)
                stopAndAlert(Alert.StartCommandServer, e.message)
                return@launch
            }
            if (config != null) {
                startService(config, disableMemoryLimit)
            } else {
                stopAndAlert(Alert.EmptyConfiguration)
            }
        }
        return Service.START_NOT_STICKY
    }

    fun onDestroy() {
        stopService()
        removeStatusObserver() // Отменяем подписку на изменения статуса
        // Отменяем все корутины при уничтожении сервиса
        serviceScope.cancel()
    }

    fun onRevoke() {
        stopService()
        removeStatusObserver() // Отменяем подписку на изменения статуса
        // Отменяем все корутины при отзыве разрешения
        serviceScope.cancel()
    }

    fun writeLog(message: String) {
        commandServer?.writeMessage(message)
    }

    fun sendNotification(notification: Notification) {
        // Отправляем уведомление через Broadcast для передачи в Flutter
        Log.d("SingBoxService", "Sending notification: ${notification.title} (${notification.typeName})")
        val intent = Intent(Action.NOTIFICATION_UPDATE).apply {
            putExtra(Action.EXTRA_NOTIFICATION_IDENTIFIER, notification.identifier)
            putExtra(Action.EXTRA_NOTIFICATION_TYPE_NAME, notification.typeName)
            putExtra(Action.EXTRA_NOTIFICATION_TYPE_ID, notification.typeID)
            putExtra(Action.EXTRA_NOTIFICATION_TITLE, notification.title)
            putExtra(Action.EXTRA_NOTIFICATION_SUBTITLE, notification.subtitle)
            putExtra(Action.EXTRA_NOTIFICATION_BODY, notification.body)
            putExtra(Action.EXTRA_NOTIFICATION_OPEN_URL, notification.openURL)
        }
        context.sendBroadcast(intent)
    }

    fun getStatus(): Status {
        return status.value ?: Status.Stopped
    }

    fun getBoxService(): io.nekohasekai.libbox.BoxService? {
        return boxService
    }
    
    /**
     * Получить адрес сервера из текущей конфигурации
     * Парсит JSON конфигурацию и извлекает адрес сервера из outbounds
     */
    fun getCurrentServerAddress(): String? {
        val config = currentConfig ?: return null
        return try {
            // Парсим JSON конфигурацию
            val jsonObject = gson.fromJson(config, com.google.gson.JsonObject::class.java)
            
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
                // Если это IP адрес или домен, возвращаем его
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
            }
            
            // Для shadowsocks адрес может быть в "settings.address"
            if (settings != null) {
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
            // Если не удалось распарсить, возвращаем null
            null
        }
    }
    
    /**
     * Отправка Broadcast с текущим статусом
     */
    private fun sendStatusBroadcast(status: Status) {
        val intent = Intent(Action.STATUS_UPDATE).apply {
            putExtra(Action.EXTRA_STATUS, statusToFlutterStatus(status))
        }
        context.sendBroadcast(intent)
    }
    
    /**
     * Преобразование Status в строку для Flutter
     */
    private fun statusToFlutterStatus(status: Status): String {
        return when (status) {
            Status.Stopped -> "disconnected"
            Status.Starting -> "connecting"
            Status.Started -> "connected"
            Status.Stopping -> "disconnecting"
        }
    }
    
    /**
     * Получение текущей статистики соединения
     * Используется для прямого запроса статистики без Broadcast
     */
    fun getConnectionStats(): Map<String, Any?> {
        val boxService = boxService ?: return getEmptyStats()
        try {
            val connections = boxService.connections()
            if (connections != null) {
                return calculateStats(connections)
            }
        } catch (e: Exception) {
            // Игнорируем ошибки, но логируем для отладки
            Log.d("SingBoxService", "Error getting connection stats", e)
        }
        return getEmptyStats()
    }
    
    /**
     * Вычисление статистики из connections
     */
    private fun calculateStats(connections: io.nekohasekai.libbox.Connections): Map<String, Any?> {
        val currentTime = System.currentTimeMillis()
        
        // Вычисляем статистику из connections
        var bytesSent = 0L
        var bytesReceived = 0L
        var minRtt: Long? = null // Минимальный RTT для ping
        
        val connectionIterator = connections.iterator()
        while (connectionIterator.hasNext()) {
            val connection = connectionIterator.next()
            bytesSent += connection.upload
            bytesReceived += connection.download
            
            // Получаем RTT (Round Trip Time) для ping
            // Пробуем получить RTT из connection через рефлексию
            try {
                // Проверяем наличие метода rtt()
                val rttMethod = connection.javaClass.getMethod("rtt")
                val rtt = rttMethod.invoke(connection)
                when (rtt) {
                    is Long -> if (rtt > 0) {
                        if (minRtt == null || rtt < minRtt) {
                            minRtt = rtt
                        }
                    }
                    is Int -> if (rtt > 0) {
                        val rttLong = rtt.toLong()
                        if (minRtt == null || rttLong < minRtt) {
                            minRtt = rttLong
                        }
                    }
                }
            } catch (e: NoSuchMethodException) {
                // Метод rtt() недоступен, пробуем latency()
                try {
                    val latencyMethod = connection.javaClass.getMethod("latency")
                    val latency = latencyMethod.invoke(connection)
                    when (latency) {
                        is Long -> if (latency > 0) {
                            if (minRtt == null || latency < minRtt) {
                                minRtt = latency
                            }
                        }
                        is Int -> if (latency > 0) {
                            val latencyLong = latency.toLong()
                            if (minRtt == null || latencyLong < minRtt) {
                                minRtt = latencyLong
                            }
                        }
                    }
                } catch (e2: Exception) {
                    // RTT/latency недоступен, оставляем null
                    Log.d("SingBoxService", "RTT/latency method not available via reflection", e2)
                }
            } catch (e: Exception) {
                // Игнорируем другие ошибки рефлексии
                Log.d("SingBoxService", "Error accessing RTT via reflection", e)
            }
        }
        
        // Вычисляем скорость (bytes per second)
        var downloadSpeed = 0L
        var uploadSpeed = 0L
        
        if (previousStatsTime > 0 && currentTime > previousStatsTime) {
            val timeDeltaMs = currentTime - previousStatsTime
            if (timeDeltaMs > 0) {
                val timeDeltaSeconds = timeDeltaMs / 1000.0
                val bytesReceivedDelta = bytesReceived - previousBytesReceived
                val bytesSentDelta = bytesSent - previousBytesSent
                
                // Вычисляем скорость в байтах в секунду
                downloadSpeed = (bytesReceivedDelta / timeDeltaSeconds).toLong()
                uploadSpeed = (bytesSentDelta / timeDeltaSeconds).toLong()
                
                // Защита от отрицательных значений (может произойти при переподключении)
                if (downloadSpeed < 0) downloadSpeed = 0
                if (uploadSpeed < 0) uploadSpeed = 0
            }
        }
        
        // Вычисляем connectionDuration
        val connectionDuration = if (connectionStartTime > 0) {
            currentTime - connectionStartTime
        } else {
            0L
        }
        
        return mapOf(
            "downloadSpeed" to downloadSpeed,
            "uploadSpeed" to uploadSpeed,
            "bytesSent" to bytesSent,
            "bytesReceived" to bytesReceived,
            "ping" to minRtt,
            "connectionDuration" to connectionDuration
        )
    }
    
    /**
     * Пустая статистика (когда соединение не активно)
     */
    private fun getEmptyStats(): Map<String, Any?> {
        return mapOf(
            "downloadSpeed" to 0L,
            "uploadSpeed" to 0L,
            "bytesSent" to 0L,
            "bytesReceived" to 0L,
            "ping" to null,
            "connectionDuration" to 0L
        )
    }
    
    /**
     * Отправка Broadcast со статистикой соединения
     */
    fun sendStatsBroadcast() {
        val boxService = boxService ?: return
        try {
            val connections = boxService.connections()
            if (connections != null) {
                val stats = calculateStats(connections)
                
                // Обновляем предыдущие значения для следующего вычисления скорости
                val currentTime = System.currentTimeMillis()
                previousBytesSent = stats["bytesSent"] as? Long ?: 0L
                previousBytesReceived = stats["bytesReceived"] as? Long ?: 0L
                previousStatsTime = currentTime
                
                // Отправляем через Broadcast
                val statsBundle = Bundle().apply {
                    putLong("downloadSpeed", stats["downloadSpeed"] as? Long ?: 0L)
                    putLong("uploadSpeed", stats["uploadSpeed"] as? Long ?: 0L)
                    putLong("bytesSent", stats["bytesSent"] as? Long ?: 0L)
                    putLong("bytesReceived", stats["bytesReceived"] as? Long ?: 0L)
                    val ping = stats["ping"] as? Long
                    if (ping != null && ping > 0) {
                        putLong("ping", ping)
                    }
                    putLong("connectionDuration", stats["connectionDuration"] as? Long ?: 0L)
                }
                val intent = Intent(Action.STATS_UPDATE).apply {
                    putExtra(Action.EXTRA_STATS, statsBundle)
                }
                context.sendBroadcast(intent)
            }
        } catch (e: Exception) {
            // Игнорируем ошибки при получении статистики, но логируем для отладки
            Log.w("SingBoxService", "Error in sendStatsBroadcast", e)
        }
    }
    
    /**
     * Запуск периодической отправки статистики
     */
    private fun startStatsBroadcast() {
        stopStatsBroadcast()
        statsJob = serviceScope.launch(Dispatchers.IO) {
            while (isActive && status.value == Status.Started) {
                sendStatsBroadcast()
                delay(STATS_BROADCAST_INTERVAL_MS)
            }
        }
    }
    
    /**
     * Остановка периодической отправки статистики
     */
    private fun stopStatsBroadcast() {
        statsJob?.cancel()
        statsJob = null
    }
    
    /**
     * Очистка ресурсов
     */
    fun cleanup() {
        stopStatsBroadcast()
        status.removeObserver(statusObserver)
    }
}

