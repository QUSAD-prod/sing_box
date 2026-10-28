package com.qusadprod.sing_box.service

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.VpnService
import android.util.Log
import com.qusadprod.sing_box.core.Paths
import com.qusadprod.sing_box.core.ServiceSettings
import com.qusadprod.sing_box.core.ServiceState
import com.qusadprod.sing_box.core.ServiceStatus

/**
 * Starts the VPN with the last config after boot (`startOnBoot`) and after an
 * app update when the VPN was running before the update killed the process.
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action
        if (action != Intent.ACTION_BOOT_COMPLETED && action != Intent.ACTION_MY_PACKAGE_REPLACED) return
        val pending = goAsync()
        Thread({
            try {
                val settings = ServiceSettings(context)
                val wanted = when (action) {
                    Intent.ACTION_BOOT_COMPLETED -> settings.startOnBoot
                    else -> settings.startOnBoot && settings.wasRunning
                }
                if (!wanted || ServiceState.status != ServiceStatus.Stopped) return@Thread
                if (Paths.readLastConfig(context) == null) {
                    Log.i(TAG, "boot start skipped: no last config")
                    return@Thread
                }
                if (VpnService.prepare(context) != null) {
                    Log.i(TAG, "boot start skipped: VPN permission not granted")
                    return@Thread
                }
                runCatching { SingBoxVpnService.start(context) }
                    .onFailure { Log.w(TAG, "boot start failed", it) }
            } finally {
                pending.finish()
            }
        }, "sing-box-boot").start()
    }

    private companion object {
        const val TAG = "sing_box"
    }
}
