package com.qusadprod.sing_box.service

import android.annotation.SuppressLint
import android.app.KeyguardManager
import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.drawable.Icon
import android.net.VpnService
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import android.util.Log
import com.qusadprod.sing_box.core.AppInfo
import com.qusadprod.sing_box.core.Paths
import com.qusadprod.sing_box.core.ServiceSettings
import com.qusadprod.sing_box.core.ServiceState
import com.qusadprod.sing_box.core.ServiceStatus

/**
 * Quick Settings tile: toggles the VPN with the last config. Declared disabled
 * in the manifest; enabled with `setServiceOptions({quickSettingsTile: true})`.
 * Reads the in-process [ServiceState], so it works without the Flutter engine.
 */
class SingBoxTileService : TileService() {
    private val listener = ServiceState.Listener { refresh() }

    override fun onStartListening() {
        super.onStartListening()
        ServiceState.addListener(listener)
        refresh()
    }

    override fun onStopListening() {
        ServiceState.removeListener(listener)
        super.onStopListening()
    }

    override fun onClick() {
        val keyguard = getSystemService(KeyguardManager::class.java)
        if (keyguard?.isKeyguardLocked == true) unlockAndRun { toggle() } else toggle()
    }

    private fun toggle() {
        when (ServiceState.status) {
            ServiceStatus.Stopped -> {
                val permitted = ServiceSettings(this).proxyMode ||
                    runCatching { VpnService.prepare(this) == null }.getOrDefault(false)
                if (!permitted || !Paths.lastConfigFile(this).isFile) {
                    openApp()
                    return
                }
                try {
                    SingBoxVpnService.start(this)
                } catch (e: Exception) {
                    Log.w(TAG, "tile start", e)
                    openApp()
                }
            }
            ServiceStatus.Starting, ServiceStatus.Started -> SingBoxVpnService.instance?.requestStop(userInitiated = true)
            ServiceStatus.Stopping -> Unit
        }
        refresh()
    }

    @SuppressLint("StartActivityAndCollapseDeprecated")
    private fun openApp() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            // The Intent overload throws UnsupportedOperationException for targetSdk 34+.
            AppInfo.launchPendingIntent(this, 3)?.let { startActivityAndCollapse(it) }
        } else {
            AppInfo.launchIntent(this)?.let {
                @Suppress("DEPRECATION")
                startActivityAndCollapse(it)
            }
        }
    }

    private fun refresh() {
        val tile = qsTile ?: return
        val settings = ServiceSettings(this)
        tile.state = when (ServiceState.status) {
            ServiceStatus.Started -> Tile.STATE_ACTIVE
            ServiceStatus.Stopped -> Tile.STATE_INACTIVE
            ServiceStatus.Starting, ServiceStatus.Stopping -> Tile.STATE_UNAVAILABLE
        }
        tile.label = settings.tileLabel ?: AppInfo.label(this)
        runCatching {
            tile.icon = Icon.createWithResource(this, AppInfo.iconResource(this, settings.notificationOptions.icon))
        }
        tile.updateTile()
    }

    companion object {
        private const val TAG = "sing_box"
        private val installed = java.util.concurrent.atomic.AtomicBoolean(false)

        internal fun component(context: Context) = ComponentName(context, SingBoxTileService::class.java)

        internal fun setEnabled(context: Context, enabled: Boolean) {
            val state = if (enabled) {
                PackageManager.COMPONENT_ENABLED_STATE_ENABLED
            } else {
                PackageManager.COMPONENT_ENABLED_STATE_DISABLED
            }
            context.packageManager.setComponentEnabledSetting(component(context), state, PackageManager.DONT_KILL_APP)
            if (enabled) requestUpdate(context)
        }

        internal fun isEnabled(context: Context): Boolean =
            context.packageManager.getComponentEnabledSetting(component(context)) ==
                PackageManager.COMPONENT_ENABLED_STATE_ENABLED

        /**
         * Asks the system to bind the tile so it can show the new state. SystemUI
         * may ignore this for tiles that are not active tiles (verified on
         * Android 17); they refresh in [onStartListening] when the panel opens.
         */
        internal fun requestUpdate(context: Context) {
            runCatching { requestListeningState(context.applicationContext, component(context)) }
        }

        /** Registers (once per process) a state listener that refreshes the tile on every change. */
        internal fun install(context: Context) {
            if (!installed.compareAndSet(false, true)) return
            val app = context.applicationContext
            ServiceState.addListener { if (isEnabled(app)) requestUpdate(app) }
        }
    }
}
