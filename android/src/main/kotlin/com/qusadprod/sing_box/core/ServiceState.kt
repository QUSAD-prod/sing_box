package com.qusadprod.sing_box.core

import android.os.Handler
import android.os.Looper
import java.util.concurrent.CopyOnWriteArrayList

/** Service state machine of the VPN service (contract: "Status values"). */
internal enum class ServiceStatus(val wire: String) {
    Stopped("disconnected"),
    Starting("connecting"),
    Started("connected"),
    Stopping("disconnecting"),
}

internal data class ServiceSnapshot(
    val status: ServiceStatus,
    /** Epoch ms of the session start, only set while [ServiceStatus.Started]. */
    val startedAt: Long?,
    /** Last start/stop failure, cleared by the next successful start. */
    val error: String?,
    /** Incremented on every successful start or reload of the box instance. */
    val generation: Long,
) {
    fun toMap(): Map<String, Any?> = mapOf(
        "status" to status.wire,
        "startedAt" to if (status == ServiceStatus.Started) startedAt else null,
        "error" to error,
    )
}

/**
 * Process-wide service state. The VPN service runs in the application's main
 * process, so every Flutter engine (and the Quick Settings tile) reads the
 * state from here, also when no Activity or engine is attached.
 */
internal object ServiceState {
    fun interface Listener {
        fun onStateChanged(snapshot: ServiceSnapshot)
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private val listeners = CopyOnWriteArrayList<Listener>()
    private val lock = Any()

    @Volatile
    var current: ServiceSnapshot = ServiceSnapshot(ServiceStatus.Stopped, null, null, 0)
        private set

    val status: ServiceStatus get() = current.status

    val isRunning: Boolean
        get() = current.status == ServiceStatus.Started || current.status == ServiceStatus.Starting

    fun update(transform: (ServiceSnapshot) -> ServiceSnapshot) {
        val changed: ServiceSnapshot
        synchronized(lock) {
            val old = current
            val new = transform(old)
            if (new == old) return
            current = new
            changed = new
        }
        dispatch(changed)
    }

    fun addListener(listener: Listener) {
        listeners.add(listener)
    }

    fun removeListener(listener: Listener) {
        listeners.remove(listener)
    }

    private fun dispatch(snapshot: ServiceSnapshot) {
        // Listeners always run on the main thread, in order of the updates.
        mainHandler.post {
            for (listener in listeners) {
                runCatching { listener.onStateChanged(snapshot) }
            }
        }
    }
}
