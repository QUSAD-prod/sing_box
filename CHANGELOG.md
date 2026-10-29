## 1.1.0

### Added
- Subscriptions by URL: `addSubscription()`, `updateSubscription()`,
  `updateSubscriptions(onlyStale:)`, `editSubscription()`,
  `removeSubscription()`, `getSubscriptions()`, `watchSubscriptions()`.
  `SingBoxSubscription` keeps the provider metadata from the response
  headers (`subscription-userinfo` traffic and expiry, `profile-title`,
  `profile-update-interval`, `profile-web-page-url`, `support-url`,
  `announce`). Servers keep stable ids across updates; stale subscriptions
  are refreshed by `initialize()`. Errors throw
  `SingBoxSubscriptionException` and are stored in `lastError`.
- Clash / mihomo YAML subscriptions: the `proxies` of ss, vmess, vless,
  trojan, hysteria, hysteria2, tuic, wireguard, socks5, http, anytls and ssh
  (with ws, grpc, h2, http and HTTPUpgrade transports) are converted by
  `SingBoxShareLink.parseSubscription()` and everything built on it. New
  dependency: `yaml`.
- IP version mode `SingBoxRoutingRules.ipVersion` (`SingBoxIpVersion.dual`,
  `ipv4`, `ipv6`) and `setIpVersion()` / `getIpVersion()`. IPv4 only
  resolves names to IPv4 and rejects IPv6 connections instead of proxying
  them, without letting IPv6 traffic leave outside the VPN.
- Routing mode `SingBoxRoutingRules.mode`: `SingBoxRoutingMode.proxyAll`
  (default) or `proxyListed`, where only the proxy lists use the VPN and the
  rest goes directly; `setRoutingMode()` / `getRoutingMode()`.
- Proxy lists that work in every mode and win over the bypass lists:
  `proxyDomains`, `proxySubnets` (`addProxyDomain()`, `addProxySubnet()`, …)
  and `blockedInCountries` (`ru`: sites and IP ranges blocked in Russia from
  runetfreedom/russia-v2ray-rules-dat; `cn`: sites outside China).
- Custom ordered rules `SingBoxRoutingRules.customRules`
  (`SingBoxRoutingRule`: proxy, direct or block by domains, suffixes,
  keywords, regexes, IP CIDRs, ports, Android apps, rule-sets by tag or URL,
  network and sniffed protocols); `setCustomRules()` / `getCustomRules()`.
- `blockQuic` and `bittorrentDirect` routing switches.
- `exportRoutingRules()` / `importRoutingRules()` (JSON).
- The plugin downloads rule-sets itself (jsDelivr mirrors for GitHub) and
  generated configs read local files, so a rule-set that cannot be
  downloaded no longer stops the VPN from starting: the rules that need it
  are left out. `getRuleSets()`, `updateRuleSets()`, `watchRuleSets()`,
  `SingBoxRuleSetStatus`, `SingBox.manageRuleSets`;
  `SingBoxConfigBuilder.ruleSetUrls()` and the `ruleSetPaths` parameter of
  `build()` / `apply()`; `SingBoxRuleSets.mirrors()`.
- Four latency methods (`SingBoxPingMethod`): `proxyHead` (default) and
  `proxyGet` time an HTTP request to `urlTestUrl` through the server -
  through the running tunnel via probe routes
  (`SingBoxConfigOptions.probeAddress`, default `198.51.100.1`), otherwise
  through a temporary core started in the app, so UDP based protocols and
  disconnected profiles are measured too; `tcp` and `icmp` are measured
  natively outside the tunnel. New `ping()`, `method` on `pingServers()`,
  `pingOutbound()` and `pingCurrentServer()`; results have `method`, `url`
  and `statusCode`.
- Crash and out-of-memory reports of the core: `getCoreReports()`,
  `deleteCoreReport()`, `deleteCoreReports()`, `SingBoxCoreReport`. Memory
  pressure recorded before the core was killed is filed when the tunnel
  starts again (like sing-box-for-android/-apple); reports carry the device
  model and OS (and on iOS the Network Extension options).
- iOS options of sing-box-for-apple in `SingBoxSettings` /
  `SingBoxServiceOptions`: `enforceRoutes`, `excludeCellularServices`
  (16.4+), `excludeDeviceCommunication` (17.4+), `excludeDefaultRoute`
  ("hide VPN icon"), `noDefaultRoute` (routes in ranges instead of a default
  route) and `excludeApnsRoute`.

### Fixed
- Android: `connect()` reported `connected` before Android routed the app
  through the VPN, so the app's first connection right after it went around
  the tunnel (reset or hang). The service now waits until the VPN is the
  app's default network (at most 3 s; not when the app is excluded).
- Android: a configuration with `wifi_ssid` / `wifi_bssid` rules but without
  the location permission now logs a warning in the core log instead of
  silently never matching.

### Changed
- `SingBoxPingMethod.urlTest` is deprecated (alias of `proxyHead`);
  `pingServers()` measures with `proxyHead` by default instead of a TCP
  handshake while the VPN is stopped.
- `bypassCountries: ['ru']` also connects the sites that only work from
  inside Russia directly (`geosite-ru-available-only-inside`).
- Requires Flutter 3.29+ / Dart 3.7+ (was Flutter 3.44+ / Dart 3.12+).
- Android: builds with AGP 9 (built-in Kotlin) and with AGP 8 plus the
  Kotlin Android plugin, as in apps created with Flutter 3.29-3.41; the
  plugin applies the Kotlin plugin itself when needed. `compileSdk` 35,
  `androidx.core` 1.13.1 and `kotlinx-coroutines` 1.7.3 as minimum versions.
- iOS: the Swift package depends on `FlutterFramework` only when Flutter
  generates that package (3.44+), so Swift Package Manager also works with
  older Flutter versions; CocoaPods is unchanged.

## 1.0.0

A complete rewrite on top of **sing-box 1.14.4** (`libbox`).

### Added
- Native libbox 1.14.4 for Android (arm64-v8a, armeabi-v7a, x86, x86_64) and
  iOS (device + simulator), downloaded at build time from GitHub releases and
  verified with SHA-256; `scripts/build_libbox.sh` builds them from source.
- Configuration generator (`SingBoxConfigBuilder`): TUN, DNS (new 1.12+
  format), routing with rule actions, selector + URL test groups, cache file,
  clash API.
- Share link and subscription parsing (`SingBoxShareLink`): VLESS (Reality,
  Vision; ws, gRPC, HTTP/2, HTTPUpgrade), VMess (v2rayN, Xray and
  Shadowrocket formats), Trojan, Shadowsocks (SIP002, SIP022, legacy,
  plugins), Hysteria/Hysteria2 (port hopping), TUIC, SOCKS, HTTP(S), AnyTLS,
  WireGuard; base64/plain/JSON/SIP008 subscriptions; export back to links.
  Unsupported transports such as XHTTP fail with a clear message. Every
  generated configuration is checked against `sing-box check` in the tests.
- `connect()` accepts links, subscriptions, outbound JSON or complete
  configs; `connectToServers()` combines profiles for instant switching.
- `connect()` completes once the tunnel is really connected and throws
  `SingBoxStartException` (exact core error), `SingBoxTimeoutException` or
  `SingBoxCancelledException`; start/stop requests are serialized so rapid
  toggles cannot leave a stale state (`waitUntilConnected: false` returns
  right after the request).
- Streams: connection state with error and start time, traffic statistics,
  logs (`watchLogs`, `watchLogBuffer`), outbound groups and outbounds with
  latencies, clash mode, connections, core notifications.
- Commands: `selectOutbound`, `urlTest`, `setClashMode`, `closeConnection`,
  `closeAllConnections`, `clearLogs`, `reload`, `restart`, `switchServer`.
- Real latency test through the proxy (`pingOutbound`, `pingCurrentServer`,
  `testGroup`), batch latency of server profiles (`pingServers`: TCP
  handshake without the tunnel, URL test through it), network quality speed
  test (`runNetworkQualityTest`,
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
- Android Always-on VPN with *Block connections without VPN* hides the Stop
  action of the notification.
- Full-featured example app and `example/lib/e2e_harness.dart` for manual
  lifecycle checks.

### Changed (breaking)
- **License: GPL-3.0-or-later** (was MIT). The native code is partly adapted
  from the official sing-box clients and the sing-box core is GPL-3.0-or-later;
  see `THIRD_PARTY_NOTICES.md`.
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
