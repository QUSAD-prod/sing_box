/*
 * Adapted from sing-box-for-android (SFA) bg/ServiceNotification.kt (GPL-3.0-or-later).
 */
package com.qusadprod.sing_box.service

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat
import com.qusadprod.sing_box.core.AppInfo
import com.qusadprod.sing_box.core.CommandSession
import com.qusadprod.sing_box.core.NotificationOptions
import io.nekohasekai.libbox.Libbox
import io.nekohasekai.libbox.StatusMessage
import kotlinx.coroutines.CoroutineScope

/** Foreground notification of the VPN service, optionally with live traffic speed. */
internal class ServiceNotification(
    private val service: SingBoxVpnService,
    private val scope: CoroutineScope,
) {
    private val manager = NotificationManagerCompat.from(service)
    private var options = NotificationOptions()
    private var builder: NotificationCompat.Builder? = null
    private var trafficSession: CommandSession? = null
    private var screenReceiverRegistered = false

    @Volatile
    private var closed = true

    fun update(newOptions: NotificationOptions) {
        options = newOptions
        builder = null
        createChannel(service, newOptions)
    }

    /** Calls `startForeground` (required immediately after `startForegroundService`). */
    fun show() {
        closed = false
        // Two-argument overload: the type comes from the manifest (systemExempted).
        service.startForeground(NOTIFICATION_ID, builder().setContentText(options.content).build())
    }

    /** Starts live ↑/↓ updates once the service is connected. */
    fun startTrafficUpdates() {
        if (!options.showTraffic || trafficSession != null) return
        if (!manager.areNotificationsEnabled()) return
        if (!screenReceiverRegistered) {
            ContextCompat.registerReceiver(
                service,
                screenReceiver,
                IntentFilter().apply {
                    addAction(Intent.ACTION_SCREEN_ON)
                    addAction(Intent.ACTION_SCREEN_OFF)
                },
                ContextCompat.RECEIVER_NOT_EXPORTED,
            )
            screenReceiverRegistered = true
        }
        val powerManager = service.getSystemService(PowerManager::class.java)
        if (powerManager?.isInteractive != false) connectTraffic()
    }

    fun close() {
        closed = true
        disconnectTraffic()
        if (screenReceiverRegistered) {
            runCatching { service.unregisterReceiver(screenReceiver) }
            screenReceiverRegistered = false
        }
        ServiceCompat.stopForeground(service, ServiceCompat.STOP_FOREGROUND_REMOVE)
    }

    private fun connectTraffic() {
        if (trafficSession != null) return
        trafficSession = object : CommandSession(Libbox.CommandStatus) {
            override fun onStatus(message: StatusMessage) {
                if (closed) return
                val speed = "↑ ${Libbox.formatBytes(message.uplink)}/s  ↓ ${Libbox.formatBytes(message.downlink)}/s"
                val text = "${options.content} · $speed"
                runCatching {
                    @Suppress("MissingPermission")
                    manager.notify(NOTIFICATION_ID, builder().setContentText(text).build())
                }.onFailure { Log.v(TAG, "update notification: ${it.message}") }
            }
        }.also { it.start(scope) }
    }

    private fun disconnectTraffic() {
        trafficSession?.stop()
        trafficSession = null
    }

    private val screenReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            when (intent.action) {
                Intent.ACTION_SCREEN_ON -> if (!closed) connectTraffic()
                Intent.ACTION_SCREEN_OFF -> disconnectTraffic()
            }
        }
    }

    private fun builder(): NotificationCompat.Builder {
        builder?.let { return it }
        val title = options.title ?: AppInfo.label(service)
        val created = NotificationCompat.Builder(service, options.channelId)
            .setShowWhen(false)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setContentTitle(title)
            .setSmallIcon(AppInfo.iconResource(service, options.icon))
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
        AppInfo.launchPendingIntent(service)?.let { created.setContentIntent(it) }
        if (options.showStopAction) {
            val stopIntent = Intent(SingBoxVpnService.actionStop(service)).setPackage(service.packageName)
            created.addAction(
                NotificationCompat.Action.Builder(
                    0,
                    options.stopActionTitle,
                    PendingIntent.getBroadcast(service, 0, stopIntent, AppInfo.immutableFlag or PendingIntent.FLAG_UPDATE_CURRENT),
                ).build(),
            )
        }
        builder = created
        return created
    }

    companion object {
        private const val TAG = "sing_box"
        const val NOTIFICATION_ID = 0x5B0C

        fun createChannel(context: Context, options: NotificationOptions) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            val manager = context.getSystemService(NotificationManager::class.java) ?: return
            val channel = NotificationChannel(options.channelId, options.channelName, NotificationManager.IMPORTANCE_LOW).apply {
                setShowBadge(false)
            }
            manager.createNotificationChannel(channel)
        }
    }
}
