## 0.1.0

A complete rewrite on top of **sing-box 1.14.4** (`libbox`).

### Added
- Native libbox 1.14.4 for Android (arm64-v8a, armeabi-v7a, x86, x86_64) and
  iOS (device + simulator), downloaded at build time from GitHub releases and
  verified with SHA-256; `scripts/build_libbox.sh` builds them from source.
- Configuration generator (`SingBoxConfigBuilder`): TUN, DNS (new 1.12+
  format), routing with rule actions, selector + URL test groups, cache file,
  clash API.
- Share link and subscription parsing (`SingBoxShareLink`): VLESS (Reality,
  Vision), VMess, Trojan, Shadowsocks, Hysteria/Hysteria2, TUIC, SOCKS, HTTP;
  export back to links.
- `connect()` accepts links, subscriptions, outbound JSON or complete
  configs; `connectToServers()` combines profiles for instant switching.
- Streams: connection state with error and start time, traffic statistics,
  logs (`watchLogs`, `watchLogBuffer`), outbound groups and outbounds with
  latencies, clash mode, connections, core notifications.
- Commands: `selectOutbound`, `urlTest`, `setClashMode`, `closeConnection`,
  `closeAllConnections`, `clearLogs`, `reload`, `restart`, `switchServer`.
- Real latency test through the proxy (`pingOutbound`, `pingCurrentServer`,
  `testGroup`), network quality speed test (`runNetworkQualityTest`,
  `testSpeed`) and STUN NAT test (`runStunTest`).
- Routing rules (`SingBoxRoutingRules`): bypass/blocked apps, domains and
  subnets, proxy-only apps, bypass LAN, bypass countries via rule-sets, ad
  blocking, custom DNS servers; applied to running tunnels immediately.
- Settings for auto connect, auto reconnect (iOS On Demand), kill switch (iOS
  `includeAllNetworks`), start on boot and a Quick Settings tile (Android).
- Permission helpers for the VPN and notifications, `openVpnSettings()`.
- Typed exceptions carrying the exact sing-box error message.
- iOS: Swift Package Manager support and a separate `SingBoxTunnel` library
  for the Packet Tunnel extension (CocoaPods pod of the same name).
- Android: built-in Kotlin (AGP 9), foreground service with live speed and a
  Stop action, Always-on VPN and boot start support.
- Full-featured example app.

### Changed (breaking)
- Requires Flutter 3.44+ / Dart 3.12+, Android API 24+, iOS 15+.
- Action methods return `Future<void>` and throw `SingBoxException`s.
- `SingBoxConnectionStatus` reduced to `disconnected`, `connecting`,
  `connected`, `disconnecting`; failures are reported in
  `SingBoxConnectionState.error`.
- `SingBoxConnectionStats` fields renamed (`uploadTotal`, `downloadTotal`,
  `duration`); the old names remain as deprecated getters.
- Routing lists moved from `SingBoxSettings` to `SingBoxRoutingRules`;
  "blocked" now means blocked, use the bypass lists to exclude traffic from
  the VPN.
- `SingBoxObserver` methods now have empty default implementations.

### Deprecated
- `watchSingBoxConnectionStatus`, `watchSingBoxConnectionStats`,
  `getActiveSingBoxServerConfig`.

### Fixed
- The Android implementation did not compile and the iOS framework was
  missing from 0.0.1.
- Talker observer could not call Talker methods and logged credentials.

## 0.0.1

- Initial release.
