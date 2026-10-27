package com.qusadprod.sing_box.core

import android.os.Handler
import android.os.Looper
import java.util.concurrent.CopyOnWriteArrayList

/** In-process bus forwarding `PlatformInterface.sendNotification` to attached engines. */
internal object CoreNotifications {
    fun interface Listener {
        fun onNotification(notification: Map<String, Any?>)
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private val listeners = CopyOnWriteArrayList<Listener>()

    fun addListener(listener: Listener) {
        listeners.add(listener)
    }

    fun removeListener(listener: Listener) {
        listeners.remove(listener)
    }

    fun publish(notification: Map<String, Any?>) {
        mainHandler.post {
            for (listener in listeners) runCatching { listener.onNotification(notification) }
        }
    }
}
