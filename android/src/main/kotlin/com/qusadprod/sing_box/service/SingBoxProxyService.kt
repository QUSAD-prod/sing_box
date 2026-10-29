package com.qusadprod.sing_box.service

/**
 * Proxy-only mode: runs a configuration without a TUN inbound (local proxy
 * inbounds such as `mixed`) as a `specialUse` foreground service, without a
 * VPN interface and without the VPN permission, like the ProxyService of
 * sing-box-for-android.
 *
 * Not declared by the plugin, so that apps which only use the VPN do not need
 * the `specialUse` foreground service declaration on Google Play: an app that
 * wants this mode declares the service and `FOREGROUND_SERVICE_SPECIAL_USE`
 * itself (see doc/android.md). It shares the lifecycle of [SingBoxVpnService];
 * the VPN specific steps are skipped through [proxyMode].
 */
class SingBoxProxyService : SingBoxVpnService() {
    override val proxyMode: Boolean
        get() = true
}
