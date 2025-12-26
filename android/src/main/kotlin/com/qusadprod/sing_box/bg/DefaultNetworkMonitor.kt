package com.qusadprod.sing_box.bg

import android.content.Context
import android.net.Network
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.nekohasekai.libbox.InterfaceUpdateListener
import java.net.NetworkInterface
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * Мониторинг сетевых интерфейсов по умолчанию
 * Скопировано и адаптировано из sing-box-for-android
 * Адаптировано для работы с контекстом вместо Application
 */
class DefaultNetworkMonitor(private val context: Context) {

    var defaultNetwork: Network? = null
    private var listener: InterfaceUpdateListener? = null
    private val networkListener = DefaultNetworkListener(context)

    suspend fun start() {
        networkListener.start(this) {
            defaultNetwork = it
            checkDefaultInterfaceUpdate(it)
        }
        defaultNetwork = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val connectivityManager = context.getSystemService(Context.CONNECTIVITY_SERVICE) as? android.net.ConnectivityManager
            connectivityManager?.activeNetwork
        } else {
            networkListener.get()
        }
    }

    suspend fun stop() {
        monitorScope.cancel() // Отменяем все корутины для предотвращения утечек
        networkListener.stop(this)
    }

    suspend fun require(): Network {
        val network = defaultNetwork
        if (network != null) {
            return network
        }
        return networkListener.get()
    }

    fun setListener(listener: InterfaceUpdateListener?) {
        this.listener = listener
        checkDefaultInterfaceUpdate(defaultNetwork)
    }

    private fun checkDefaultInterfaceUpdate(
        newNetwork: Network?
    ) {
        val listener = listener ?: return
        if (newNetwork != null) {
            val connectivityManager = context.getSystemService(Context.CONNECTIVITY_SERVICE) as? android.net.ConnectivityManager
            if (connectivityManager == null) {
                listener.updateDefaultInterface("", -1, false, false)
                return
            }
            val interfaceName = connectivityManager.getLinkProperties(newNetwork)?.interfaceName ?: run {
                listener.updateDefaultInterface("", -1, false, false)
                return
            }
            
            // Используем корутину вместо Thread.sleep для неблокирующей задержки
            monitorScope.launch {
                for (times in 0 until NETWORK_INTERFACE_RETRY_COUNT) {
                    var interfaceIndex: Int
                    try {
                        interfaceIndex = NetworkInterface.getByName(interfaceName)?.index ?: -1
                        if (interfaceIndex == -1) {
                            delay(NETWORK_INTERFACE_RETRY_DELAY_MS)
                            continue
                        }
                    } catch (e: Exception) {
                        delay(NETWORK_INTERFACE_RETRY_DELAY_MS)
                        continue
                    }
                    listener.updateDefaultInterface(interfaceName, interfaceIndex, false, false)
                    return@launch
                }
                // Если не удалось получить индекс после всех попыток
                listener.updateDefaultInterface(interfaceName, -1, false, false)
            }
        } else {
            listener.updateDefaultInterface("", -1, false, false)
        }
    }

}

