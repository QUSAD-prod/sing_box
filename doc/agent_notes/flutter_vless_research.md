# flutter_vless research (for our sing-box/libbox Flutter plugin)

Status: COMPLETE (research agent, 2026-10-27). Raw notes first; FINAL REPORT (A/B/C) at the bottom.

Sources: https://github.com/XIIIFOX/flutter_vless (cloned depth 1 at 2026-10-27, last push 2026-10-25),
GitHub REST API issues/PRs, pub.dev.

## Raw facts (repo metadata)
- Repo created 2025-08-29, NOT a GitHub fork (parent=null), MIT license, 53 stars, 24 forks, 3 open issues (at 2026-10-27).
- Description: "Cross-platform Xray/V2Ray VPN plugin for Flutter: VLESS Reality/XHTTP, VMess, Trojan, Shadowsocks, SOCKS5, Hysteria2 and WireGuard on Android, iOS, macOS and Windows."
- Repo is ~709MB (binaries in tree), very large tool/ dir with test harnesses (python/swift/cpp).

## pub.dev versions
- flutter_vless: 1.0.0 (2025-09-23), 1.0.1 (11-07), 1.0.2 (11-21), 1.0.3 (11-27), 1.0.4 (12-10), 1.0.5 (2026-05-23), 1.1.0 (05-26, desktop federated split), 1.1.1 (06-03), 1.1.2 (06-20), 1.1.3 (07-01), 1.1.4 (07-09), 1.1.5 (07-27), 1.1.6 (09-15, latest)
- flutter_vless_android latest 1.1.7 (2026-10-17); flutter_vless_macos 1.1.7; flutter_vless_windows 1.1.7; flutter_vless_platform_interface 1.1.2
- NB: 5-month gap Dec 2025 -> May 2026 with iOS build issues unanswered (#5,#6,#7,#8 all answered only 2026-05-22 "We updated the iOS part").

## Issue catalogue raw notes (all 28 issues/PRs read with comments)
- #1 pc? (enh) -> desktop branch, Win+macOS experimental; closed when PR #11 Desktop merged 2026-05-26.
- #2 PR Feature/kotlin android (maintainer, 2025-11-21) — Android rewritten in Kotlin.
- #3 "No such module 'XRay'" iOS (2025-11) -> user must manually drag XRay.xcframework into flutter_vless pod target in Xcode (screenshot). Doc issue.
- #4 VPN not working on iOS: shows `connected` but no traffic (VPN and proxy mode). Closed same day w/o fix. Later commenter: switched to dima-u/SwiftyXrayKit; posted fork commit with example/ios changes for working tunnel.
- #5 SwiftCompile fails in NE target, Xcode 26.1.1 / Swift 6.2.1 internal compiler error "PHINode should have one entry for each predecessor" in PacketTunnelProvider.startTunnel (async override + fatalError guards). Answer 5 months later: "updated iOS part, see example + IOS_SETUP.md".
- #6 (by our user QUSAD-prod) SwiftCompile failed, same PacketTunnelProvider template (copy-pasted into app). Template shows the 1.0.x iOS design: providerConfiguration["xrayConfig"] Data; NEPacketTunnelNetworkSettings(tunnelRemoteAddress "254.1.1.1"), mtu 9000, IPv4 198.18.0.1/16 default route, IPv6 fd6e:a81b:704f:1211::1/64 default route, DNS 8.8.8.8 + 114.114.114.114 (Chinese DNS hardcoded!), XRayStart(config, logger) + HEV Socks5Tunnel (tun2socks) to local socks inbound port parsed from config; handleAppMessage "xray_traffic" returns HEV stats up,down; "xray_delay<url>" calls XRayMeasureDelay; sleep/wake empty; XRaySetMemoryLimit(). Fix: same as #5.
- #7 "Cycle inside Runner" (Xcode build cycle when embedding .appex) -> answered with "updated iOS part". (Known fix in general: move "Embed Foundation Extensions"/"Embed App Extensions" build phase above "Run Script"/"Thin Binary" in Runner target — not stated in thread; general Flutter knowledge.)
- #8 How to generate Xray.xcframework -> added ios/build_xray_ios.sh (gomobile) in 2026-05.
- #9 macOS? -> dup of #1.
- #10 iOS ss:// connects but no traffic (vmess works). Maintainer: "not all ss:// configs compatible... no plans to adapt". Unresolved (closed wontfix-ish).
- #11 PR Desktop (maintainer) merged 2026-05-26.
- #12 macOS compile error 1.1.1: SwiftPM can't resolve `.packages/flutter_vless_macos`; iOS: `../FlutterFramework` missing in published package when ios/flutter_vless added directly from pub cache. Fix: fallback ios/FlutterFramework SwiftPM package in next release; workaround use Flutter-generated path ios/Flutter/ephemeral/Packages/.packages/flutter_vless-1.1.1; deployment target >= 15.0.
- #13 (30 comments) macOS 1.1.2 compile error `cannot find type 'XRayLoggerProtocol'` (pub artifact mismatch between Swift sources and bundled xcframework). Long back-and-forth: needed ../tool/prepare_apple_swiftpm.sh script, repo folder must be named exactly `flutter_vless` (SwiftPM package identity from folder name), delete Package.resolved, rm -rf macos/Flutter/ephemeral Pods Podfile.lock, old Xcode can't read project format (they added Xcode 15 compatible project files). Then runtime didn't work: cause = Runner and XrayTunnel must share Apple Team + App Group, and initializeVless() must get base app bundle id (user had example's dev.tfox.flutterXrayExample). Fixed in 1.1.3. LESSON: setup complexity + identifiers hardcoded in example.
- #14 Windows compile: generated_plugin_registrant.cc includes <flutter_vless_windows/flutter_vless_plugin.h> but header is at flutter_vless/… (federated package header path mismatch). Workaround: edit generated file each run. Fixed (PR #27 forwarding header) only 2026-09. User also said after workaround "package does not fulfill its main task" (VPN not working on Windows).
- #15 Android "Blocked Apps" didn't work at all (even in example) + Windows VPN mode: multiple CMD windows flash (spawning netsh/route via cmd), then no traffic or upload counter grows abnormally fast with no activity (routing loop). Reporter later: reboot fixed Windows. Android part fixed by PR #18.
- #16 WireGuard via Xray core -> already on main, release 1.1.3.
- #17 (by our user QUSAD-prod, iOS) "Connection drops": after some time (app fg or bg) either system VPN shows connected but no traffic until reconnect, or system VPN disconnects. Did not happen on Dec 2025 version. Cursor analysis: (a) HEV tun2socks thread exits → no cancelTunnelWithError → zombie "connected"; (b) HEV read-write-timeout 60000ms kills idle TCP; (c) health check only once at start (0.5s); (d) sleep()/wake() no-ops — no recovery after network change. Maintainer fixed on main (commit 99b22b5d…), user confirmed on iOS 2026-07-25. Exact fix contents: TODO check CHANGELOG.
- #18 PR: Android BLOCKED_APPS received but never applied to VpnService.Builder (only own package disallowed) → loop addDisallowedApplication(pkg). Merged 2026-07-19.
- #19 iOS dynamic geoip.dat/geosite.dat from App Group: setting XRAY_LOCATION_ASSET via setenv() in Swift after Go runtime init does not affect Go os.LookupEnv → Xray looked only in NE bundle resources ("common/geodata: failed to open geosite.dat"). Implemented geoAssetsDirectory in e4f8aa81 (Go-runtime asset lookup configuration). LESSON: for sing-box use rule-set (.srs) remote/local files in shared container; pass paths via config/libbox setup, never env after Go init.
- #20 Apple Packet Tunnel: SOCKS CONNECT ok but HTTP/HTTPS fail for VLESS TCP+Reality+Vision → turned out user's macOS account got a different server config (user error). Interesting: debug log reveals 1.1.5 Apple design: resolves server domain to IPv4 & excludes route, forces local socks-in → proxy outbound, adds UDP/443 block rule to force TCP fallback (QUIC blocked!), "Could not read packetFlow socket file descriptor" via KVC → fallback scanning for utun fd for HEV, several health checks (SOCKS, CONNECT, server TCP route, HTTP, URLSession HTTPS to google generate_204).
- #21 PR (open) Android Quick Settings tile (VlessTileService): persisted last profile; review blockers: Android 14+ TileService.startActivityAndCollapse(Intent) throws for targetSdk 34+ → use PendingIntent overload w/ fallback; don't request VPN permission for proxy-only; tile state stale when Flutter engine gone → persist CONNECTED/DISCONNECTED from VPN process + TileService.requestListeningState. Still unmerged at 2026-10.
- #22 feature request: Quick Settings tile (API proposal QuickSettingsTile(tileLabel, tileIconResourceType/Name)).
- #23 iOS NE jetsam kill (50 MB ActiveHard) on VLESS Reality+XHTTP stream-up under concurrent uploads. Root cause: Go h2 client per-stream upload scratch buffer = min(server SETTINGS_MAX_FRAME_SIZE, 512KB); Xray XHTTP server advertises 1MB → 512KB per stream ×35–45 streams = 18–23 MB. Go>=1.25 x/net/http2 client wraps stdlib net/http/internal/http2 so must patch GOROOT clone (`const max = 512 << 10` → 128<<10 / 16<<10) before gomobile bind. Upstream XTLS/Xray-core#6663. PR #24 merged (default 128KiB, H2BUF_CAP_KB env). RELEVANT TO US: sing-box also may use Go h2 (e.g., gRPC/HTTP transports? sing-box's v2ray HTTP transport uses golang.org/x/net/http2 or stdlib) — memory risk in iOS NE; check libbox memory limits (sing-box has `SetMemoryLimit` / experimental memory limiter on iOS).
- #24 PR for #23 merged 2026-08-27.
- #25 Linux support request (open, PR Welcome).
- #26 PR runtime inputs iOS r3 (XRayStartPrivate, structured private diagnostics) / Android protect1 (protected transport/DNS broker overlay → socket protect broker).
- #27 PR fix macOS CI signing + Windows forwarding header.
- #29 Android INVALID_CONFIG when streamSettings.security none: Xray-core v26.9.9 rejects VLESS outbound to public address with both security none and encryption none (upstream validation infra/conf/xray.go). Error message generic "VPN configuration was rejected; the active session was preserved". LESSON: surface core's actual error text to Dart.

## Package code study (main @ 2026-10-25; unreleased 1.1.7 train)

### Federated layout
- flutter_vless (app-facing + iOS impl in root ios/), flutter_vless_platform_interface, flutter_vless_android, flutter_vless_macos, flutter_vless_windows. No Linux (#25 open).
- MethodChannel 'flutter_vless', EventChannel 'flutter_vless/status'.
- Fork origin evidence: Android code still uses AppConfigs.V2RAY_STATE / V2RAY_STATES.V2RAY_CONNECTED / V2RAY_CONNECTION_INFO / V2RAY_SERVICE_COMMANDS, process name ":RunSoLibXrayDaemon" (flutter_v2ray had ":RunSoLibV2RayDaemon"), CHANGELOG 1.0.1 "modify V2rayCoreManager to use CoreController". => derived from flutter_v2ray (pub: flutter_v2ray by amir-zr) lineage; repo itself is not a GitHub fork. NOTICE claims copyright 2024-2026 13FOX Studio.

### Public Dart API (FlutterVless)
- ctor FlutterVless({onStatusChanged}) ; callback only, NO Stream, NO getStatus()/current-state query.
- initializeVless({notificationIconResourceType, notificationIconResourceName, providerBundleIdentifier (base bundle id; '.XrayTunnel' appended internally on Apple), groupIdentifier, keychainAccessGroup?, options: VlessOptions?})
- requestPermission() -> bool (Android VpnService.prepare + notif perm)
- startVless({remark, config (Xray JSON string), notificationDisconnectButtonName='DISCONNECT', blockedApps (Android pkgs), bypassSubnets (CIDR; iOS VPN rejects non-empty w/ INCOMPATIBLE_ROUTING; mac/win translate IPv4 to xray direct rules), proxyOnly, geoAssetsDirectory, certificateAssetsDirectory, androidDnsPolicy {config, proxy}, androidDnsProxyOutboundTag, vpnRouting: VpnRoutingOptions(sourceInboundIndex, defaultOutboundTag)})
- startVlessWithReport(...) -> VlessPreparationReport (closed codes: coreCheck passed/unavailable, scope host/runtimeFinal, changes list)
- stopVless()
- getServerDelay({config, url='https://google.com/generate_204', geoAssetsDirectory, certificateAssetsDirectory}) -> int ms or -1 (Windows standalone delay unsupported -> -1)
- getConnectedServerDelay({url}) -> int
- getCoreVersion() -> String ; getProviderDebugSnapshot() -> String (bounded human-readable logs)
- getCapabilities() -> VlessCapabilities(optionsVersion, quickAccessSurfaces, requestAddQuickTile, controlCenterExtensionConfigured, customReconnectBackoff, onDemand, alwaysOn, alwaysOnEnabled, lockdownEnabled, killSwitch)
- requestAddQuickTile() -> QuickTileAddResult {added, alreadyAdded, declined, unsupported}; clearQuickAccessProfile()
- static parse(input) / parseMany(subscription) / parseFromURL(url) -> FlutterVlessURL (VmessURL, VlessURL, TrojanURL, ShadowSocksURL, SocksURL, Hysteria2URL, XrayJsonConfig); .remark, .getFullConfiguration(indent), .outbound1, mutable inbound/routing/log/stream maps; typed XrayConfigDocument model + XrayConfigValidator.
- VlessStatus {duration s, uploadSpeed, downloadSpeed, upload, download (bytes), state raw string, connectionState enum connected/connecting/disconnected/disconnecting/unknown}. Wire format: legacy positional List<String>[duration, upSpeed, downSpeed, upTotal, downTotal, state] or Map. NO error/reason field in status.
- VlessOptions: NotificationOptions(iconResourceType/Name, buttonLabel, action disconnect/openApp/none), QuickAccessOptions(enabled, surface, label, action toggle/openApp, requireUnlock, androidIconResourceName, appleSymbol, windowsIconPath), ReconnectOptions(enabled, initialDelay, maxDelay, maxAttempts 0=unlimited), ProtectionOptions(killSwitch platformDefault/required, onDemand platformDefault/enabled/disabled, alwaysOn system/requireEnabled), DiagnosticsOptions(enabled, maxBytes, maxLines).
- Errors: PlatformException codes e.g. INVALID_CONFIG ("VPN configuration was rejected; the active session was preserved"), INCOMPATIBLE_ROUTING, VPN_STOP_ERROR, VPN_START_CANCELLED; VlessConfigurationFailure.fromDetails(details) for closed failure stage.
- Dart-side generation counter cancels stale capability-gated starts (race Start/Stop).

### Android implementation (flutter_vless_android, Kotlin)
- Runtime AAR on Maven Central dev.tfox.fluttervless:xray-android:<xray ver>-protect1 with libxray.so + libtun2socks.so (4 ABIs) + geoip/geosite. Pub package excludes binaries (pub size limit).
- Xray and tun2socks are EXECUTABLES launched via ProcessBuilder from nativeLibraryDir -> REQUIRES `packaging.jniLibs.useLegacyPackaging = true` / extractNativeLibs=true (bigger APK install size; Play warns). 
- tun2socks config yaml: proxy socks5://user:pass@127.0.0.1:port, mtu 1500; TUN fd passed over LocalSocket (-sock-path) with SCM_RIGHTS.
- VpnService.Builder: setSession(remark), MTU 1500, 26.26.26.1/30 + fd26:26:26::1/126 (v2rayNG-like), routes 0.0.0.0/0 and ::/0, setMetered(false), addDisallowedApplication(blockedApps) (bug #18 fixed 1.1.5), DNS virtual 10.0.85.53. Earlier versions disallowed own package (whole app UID bypassed VPN) — changed in 1.1.6 to use socket protect broker (Go overlay xray-protect calls VpnService.protect via broker).
- Services in separate process ":RunSoLibXrayDaemon" (VPN service + TileService), FGS type specialUse subtype "vpn" (0x40000000), SUPPORTS_ALWAYS_ON=true. Manifest includes READ_EXTERNAL_STORAGE (unneeded, store-review smell), POST_NOTIFICATIONS, FOREGROUND_SERVICE_SPECIAL_USE.
- Notification: channel "vpn_service_channel" IMPORTANCE_LOW, title=remark, text Connected/Recovering..., action Disconnect (hidden when always-on/lockdown) or openApp.
- Status: VPN service ticks every 1 s → publishState → sendBroadcast(intent with STATE, DURATION, speeds, totals) → plugin BroadcastReceiver registered ON ACTIVITY only (none when activity detached) → EventChannel list payload. Traffic read by spawning `libxray.so api statsquery --server=127.0.0.1:<api> --pattern inbound>>>tag>>>traffic>>>` PROCESS EVERY SECOND (battery/CPU cost); speed = delta per tick.
- Health: every 30 ticks authenticated SOCKS + packet path probe; network callback (NOT_VPN INTERNET onAvailable/onLost) triggers recovery; recovery keeps TUN established (kill-switch) with capped backoff; status CONNECTING during recovery.
- Session restore after process death: authorized profile encrypted with Android Keystore in noBackupFilesDir (for always-on / sticky restart).
- Delay (getServerDelay): spawns a separate whole Xray process per test with temp config + authenticated SOCKS inbound, retries up to 20×100ms, measures ONE `HEAD <path>` through SOCKS incl. connect+TLS (System.nanoTime) → single sample, -1 on any failure. Connected delay executes in service process via the running core. Default delay URL in service: https://www.gstatic.com/generate_204.

### iOS implementation (root package ios/, current main)
- XRay.xcframework (gomobile bind of third_party/xray-mobile wrapper: Start/StartPrivate(config, logger), Stop, GetVersion, SetAssetLocation, SetMemoryLimit = debug.SetGCPercent(10)+SetMemoryLimit(30MB), QueryStats(tag) via VisitCounters, MeasureDelay/MeasureOutboundDelay = STUBS returning 0!) + Tun2SocksKit 5.15.0 (HEV hev-socks5-tunnel 2.15) in the Packet Tunnel extension. Distributed via SwiftPM binary target download w/ checksum (hosted GitHub releases xray-ios-vXX) or CocoaPods fallback; 1.0.x required manually copying XRay.xcframework into app (#3).
- Integrator MUST create a Packet Tunnel target named exactly `XrayTunnel` (bundle id = <base>.XrayTunnel), App Group on both, shared Keychain group (1.1.6+), iOS 15+, and COPY example/ios/XrayTunnel/PacketTunnelProvider.swift (1364 lines now) into their target; "Updating the Dart dependency alone does not update an application's extension source" → constant drift between plugin and copied provider (source of #5/#6/#17-type bugs).
- Config handoff: originally providerConfiguration["xrayConfig"] Data (plaintext in VPN profile); since 1.1.6 stored in shared Keychain item, profile stores opaque persistent ref (VPN_KEYCHAIN_ERROR if device not unlocked since boot).
- Network settings (provider): tunnelRemoteAddress 254.1.1.1, MTU 1500 (was 9000 in 1.0.x), IPv4 10.0.85.2/24 default route + virtual DNS 10.0.85.53 (/32) included; excluded routes = server bootstrap IPv4 literals; IPv6 fd00:198:18::1/64 default route captured (blocked; AAAA NODATA while IPv4-only forwarding); DNS matchDomains [""]. Manager: includeAllNetworks = TRUE, excludeLocalNetworks = FALSE (mandatory "traffic protection" since 1.1.6 — no opt-out; breaks LAN/AirPlay/etc. — side effects not documented in repo [my note]), On Demand NEOnDemandRuleConnect for recovery; explicit stop disables On Demand first.
- HEV config: socks5 127.0.0.1:<port> user/pass, udp 'udp', pipeline false, task-stack-size 86016, tcp-buffer-size 65536, max-session-count 512, connect-timeout 5000, tcp-read-write-timeout 300000 (was 60000 → #17 idle drops), udp-read-write-timeout 60000.
- 1.1.5: detects unexpected HEV exit + repeated health-check failures → cancel tunnel (fixes zombie connected, #17); periodic + post-wake/network-change health checks; bounded App Group diagnostics/log rotation (extension I/O & memory). macOS: HEV connected through public NEPacketTunnelFlow read/write + socketpair instead of KVC private packetFlow fd lookup/utun fd scanning (1.1.6).
- Status/traffic: app-side 1 s Timer → sendProviderMessage("xray_traffic") → provider returns HEV stats "up,down" (VPN) ; proxy-only uses XRayQueryStats. NEVPNStatusDidChange observer maps status; on init with existing connection restarts timer (connectedDate). Events delivered on platform thread since 1.1.7 (earlier off-main delivery bug).
- Delay: getConnectedServerDelay → provider message "xray_delay<url>" → Swift LocalProxyDelayClient (raw SOCKS5 auth socket + own TLS (TLS1.2 only on iOS15 path: TLS1.3-only dest returns -1) + GET, 8 s connect/10 s deadline, one sample). Standalone getServerDelay runs XRayStartPrivate in APP process with temp config → returns -1 while proxy-only runtime active (single global Go core instance). In 1.1.5 logs "XRay internal delay health check: ok delay=0ms" (stub MeasureDelay) [likely older versions' iOS connected delay = 0 — UNVERIFIED for 1.0.x].
- proxy-only on iOS = Xray inside the app process (dies/suspends when app backgrounded) [inference].
- Memory: NE 50 MB jetsam; XRaySetMemoryLimit (GC 10%, 30 MB soft limit); h2 buffer patch (#23). 

### 1.0.x (what user used Dec 2025)
- 1.0.0 shipped android/libs/libv2ray.aar (AndroidLibXrayLite, v2rayNG core) + badvpn-like libtun2socks.so jniLibs inside the pub package; API: FlutterVless(onStatusChanged), initializeVless(providerBundleIdentifier e.g. 'com.example.myapp.VPNProvider' (full ext id in 1.0.x; base id since 1.0.5!), groupIdentifier), requestPermission, startVless(remark, config, blockedApps, bypassSubnets, proxyOnly), stopVless, getServerDelay(config,url), getConnectedServerDelay(url), getCoreVersion, parseFromURL. Required android:extractNativeLibs="true". README almost identical to flutter_v2ray's.
- 1.0.4 IOS_SETUP.md: copy XRay.xcframework into ios/, Podfile platform 15, add XrayTunnel NE target, add Tun2SocksKit SPM (EbrahimTahernejad), XRay.xcframework + libresolv.tbd, paste PacketTunnelProvider.swift, "Move Embed Foundation Extensions to the bottom of Copy Bundle Resources" (fix for "Cycle inside Runner" #7). This mirrors flutter_v2ray_client iOS setup [verify].

## Upstream lineage: blueboy-tm/flutter_v2ray (pub flutter_v2ray 1.0.10, 172★, Android-only, 115 issues/PRs read)
Architecture (old): Java, libv2ray.aar (2dust AndroidLibV2rayLite / libgojni.so) + badvpn tun2socks executable, V2rayVPNService in ':RunSoLibV2RayDaemon', status via broadcast V2RAY_CONNECTION_INFO. flutter_vless 1.0.0 = this design + iOS (XRay.xcframework+Tun2SocksKit, flutter_v2ray_client-style setup). Siblings: amir-zr/flutter_v2ray_client (pub 3.5.0; claims Android/iOS/Win/mac/Linux, WireGuard, Hysteria2), shafiquecbl/flutter_v2ray_plus (copy of flutter_vless 1.0.x description; author filed flutter_vless #3/#4), shayanheidari01/flutter_v2ray fork. Upstream maintainer bulk-closed ~20 old issues 2026-10-22 as "fixed on modernization branch".
Notable upstream problems (all Android unless noted):
- #1/#2 app crashes on reopen while VPN connected (fixed 2023). #103 crash in daemon: onStartCommand with null Intent (sticky restart) → NPE; plus "Background execution not allowed: receiving Intent V2RAY_CONNECTION_INFO" manifest receiver. Fix: null-intent handling, remove manifest receiver.
- #24/#26/#30 1.0.5 regression: VPN disconnects after 3–11 s on newer Androids (fix PR #31). #47 after app terminated VPN gets slow after ~15 min. #33 rapid start/stop ×10 → stop no longer works (no serialization).
- #50/#71 targetSdk 34: registerReceiver must specify RECEIVER_EXPORTED/NOT_EXPORTED. #72 targetSdk 34 → connected but no internet; #94/#116/#111 minSdk ≥23 → connected, no traffic: root cause = native libs not extracted (AGP default useLegacyPackaging=false for minSdk≥23) so tun2socks executable missing. Workaround: `packaging { jniLibs { useLegacyPackaging = true } }` + android:extractNativeLibs="true". (Most common "connected but no internet" cause.)
- #66 BackgroundServiceStartNotAllowedException: Context.startService(STOP) from background → use in-process stop broadcast/stopService. 
- #59/#77/#107 Android 13 notification missing (POST_NOTIFICATIONS), ANR when user blocks notifications; must still startForeground() promptly and move native work off main thread. #98 NPE in onActivityResult (null pending result) — permission flow lifecycle.
- #37/#23/#22/#101 customize/disable notification (title, icon, text, disconnect button, speed in notification). #36 Quick Settings tile can't re-enable VPN. #34/#95 exclude apps / per-app proxy.
- #6/#89 proxy-only "connected but speed zero" (stats only counted for tun traffic / user didn't route through proxy). #67/#86 traffic stats stuck at 0 or jumpy ints (speed computed per tick; 0 most ticks). #7 reset traffic on disconnect.
- #8/#53/#78 delay: getServerDelay blocks/crashes while connected or on timeout ("You cannot get a delay while connecting to a VPN"); requested batch ping of many configs concurrently like v2rayNG (40 configs in ~2 s, one thread per config). #78 getConnectedServerDelay errors while connected (fixed PR #77).
- #90 no initial status event until connected → need getStatus()/initial state emit.
- #15/#18/#43 YouTube over Wi-Fi / Irancell fails — IPv6 & DNS issues (fixed DNS). #64 release-mode connected no internet → "bypass local network". #3/#9/#68 Reality / xtls-rprx-vision / domain address issues (old core). #65 TLS. #109 balancer configs unsupported. #49 fragments/custom config. #60 DoH DNS. #83/#80/#11/#29/#57 routing management, geoip/geosite, bypass LAN & mainland. #63 hysteria, #106/#91/#70 core updates lag.
- #115/#112/#114/#119/#120 16 KB page size required by Google Play (Nov 2025 deadline) — .so must be 16K-aligned; #121 Google Play Protect flags APK as unsafe. #118 duplicate libgojni.so conflict with other gomobile libs (openvpn_flutter) — mergeNativeLibs fails. 
- #13/#14/#17/#21/#40/#54/#58/#69/#73/#102/#113 iOS/desktop requests (most demanded feature); #79 hotspot sharing; #105 background monitoring of state/data usage when app closed.

## shafiquecbl/flutter_v2ray_plus (copy of flutter_vless 1.0.x; issues = flutter_vless 1.0.x bugs reported in the fork)
- #2 flutter_vless maintainer filed "License violation — attribution required (MIT)" → fork added attribution. (License lesson: MIT attribution; flutter_vless NOTICE/TRADEMARKS now demand notice preservation.)
- #3/#5 Swift 6.2.1 PHINode compiler crash in PacketTunnelProvider.startTunnel (async override + guard/fatalError + nested closures). Workaround: rewrite startTunnel with completion-handler API (override func startTunnel(options:completionHandler:)), no fatalError, helper methods. Then "This Connection Is Not Private" in Safari → ordering bug: must setTunnelNetworkSettings → wait → start Xray → wait SOCKS ready → start tun2socks.
- #4 VPN fails only when installed from Google Play (not local release) → `packaging.jniLibs.useLegacyPackaging = true` + android:extractNativeLibs="true" (AAB split installs don't extract native libs → executables missing).
- #6 v1.0.10 Kotlin syntax errors broke build (no CI). #7 blockedApps not applied (lost in Java→Kotlin rewrite; same as flutter_vless #18). 
- #10 iOS status stuck CONNECTED with duration 0 after rapid connect/disconnect; stopVless doesn't help (no serialization of start/stop; stale manager/timer).
- #13 WhatsApp doesn't work through iOS tunnel (tried includeAllNetworks/excludeLocalNetworks/excludeAPNs/enforceRoutes, MTU 1500/9000) — open. [likely UDP/STUN/push (APNs) / IPv6 handling; unverified]
- #14 speed fields show cumulative traffic instead of rate (bug). #15 Android copyAssets() overwrites custom geoip/geosite on every connect → can't use runtime-updated geo files; Xray fatal if rule category missing. #16 Android startVless() always returns success even if Xray fails; status reflects VpnService not core. #17 how to prevent user connecting from iOS Settings (profile visible in Settings > VPN; can be toggled without app). #18 iOS Shadowsocks connects then disconnects (same as flutter_vless #10). #11 asks Tun2SocksKit alternatives (leaf). #19 is NE entitlement required on iOS (yes).

## amir-zr/flutter_v2ray_client (sibling) notable
- #3 expose Xray core logs (implemented v3.0.0). #15 stats always 0 (core compiled without stats). #21/#24 "stops after ~20 s"/"doesn't connect on Flutter > 3.29": `Cannot run program .../libtun2socks.so: No such file` → extractNativeLibs / useLegacyPackaging. #22 ANR startForegroundService() did not call startForeground() (Android 14). #23 IntentReceiverLeaked when app killed while connected (receiver lifecycle). #29 only Telegram/Instagram work, browsers don't (open). #33 Vivo: tun2socks executable SELinux AVC denial → VoIP UDP dies (exec-ing binaries from app dir is fragile on OEM ROMs).

## Misc verified facts
- Fix for #17 = commit a412b0026 "Harden Apple packet tunnel lifecycle" (2026-07-19), released in 1.1.5 (HEV exit detection → cancel tunnel; periodic + post-wake/network-change health checks; bounded logs). HEV tcp-read-write-timeout now 300 s.
- Licenses: Xray-core = MPL-2.0 (so flutter_vless can be MIT). sing-box = GPL-3.0-or-later + extra term "no derivative work may use the name or imply association with this application without prior consent" (README). → our plugin linking libbox is GPL-bound; App Store + GPL tension; can't call it "sing-box ..." without consent.
- flutter_vless docs contain nothing on App Store / Play review, privacy manifest, macOS Developer ID / System Extension distribution (grep empty).
- security.md: iOS profile sets includeAllNetworks, disables excludeLocalNetworks/excludeAPNs/excludeCellularServices "where supported"; on-demand restart after provider termination is iOS-scheduled.

==========================================================================================
# FINAL REPORT (A/B/C) — research complete 2026-10-27
==========================================================================================

## A. Package overview

### A1. Identity and history
- XIIIFOX/flutter_vless (13FOX Studio / tfox.dev), MIT. Not a GitHub fork, but its code descends from blueboy-tm/flutter_v2ray (Android, Java). The Android code still uses V2RAY_STATE / V2RAY_CONNECTION_INFO / ":RunSoLib…Daemon". 1.0.0 shipped 2dust libv2ray.aar plus a tun2socks executable. The iOS setup copies the flutter_v2ray_client approach: XRay.xcframework + Tun2SocksKit/HEV.
- Releases: 1.0.0 (2025-09) to 1.0.4 (2025-12). Then a five-month gap with iOS build issues unanswered. Then 1.0.5 (2026-05-23: SwiftPM, base bundle id) and 1.1.0 (federated split; macOS and Windows, proxy-only). 1.1.3 added WireGuard/Hysteria2 import and fixed macOS. 1.1.5 (07-27) fixed the #17 drops and blockedApps. 1.1.6 (09-15) is the latest root package: mandatory kill-switch, Keychain storage, local proxy auth, geoAssetsDirectory, h2 memory cap. Platform packages are at 1.1.7 (2026-10-17), but the README says the pub 1.1.7 packages "contain older wrapper code". The real 1.1.7 lives only on git main.
- Core: Xray-core, pinned per release (26.6.x → 26.10.21). It is shipped as separately published binaries: Maven Central AAR dev.tfox.fluttervless:xray-android:<ver>-protect1, GitHub-release XCFrameworks for iOS and macOS fetched by SwiftPM/CocoaPods with checksums, and a user-supplied xray.exe + tun2socks.exe + wintun.dll on Windows. No Linux and no web (#25 open).

### A2. Architecture per platform
- **Android** (Kotlin, flutter_vless_android):
  - libxray.so and libtun2socks.so are executables started with ProcessBuilder from nativeLibraryDir. Apps therefore need packaging.jniLibs.useLegacyPackaging=true / extractNativeLibs=true.
  - VpnService runs in process ":RunSoLibXrayDaemon". FGS type specialUse with subtype "vpn"; SUPPORTS_ALWAYS_ON=true.
  - Builder: MTU 1500; 26.26.26.1/30 and fd26:26:26::1/126; default routes for v4 and v6; setMetered(false) unconditionally; addDisallowedApplication(blockedApps); virtual DNS 10.0.85.53. No setUnderlyingNetworks call found (grep).
  - The TUN fd goes to tun2socks over a LocalSocket (SCM_RIGHTS). tun2socks talks to an authenticated loopback SOCKS inbound that the plugin injects into the Xray JSON.
  - Since 1.1.6 the app UID is no longer excluded. Core sockets bypass the VPN through a Go "protect broker" overlay instead.
  - Recovery keeps the TUN up (kill-switch) and retries with capped backoff, reporting CONNECTING meanwhile. A NetworkCallback (INTERNET + NOT_VPN) triggers recovery. A Keystore-encrypted profile allows Always-on/sticky restarts without the app.
  - Status: a 1 s tick sends a broadcast. The plugin's BroadcastReceiver is registered on the Activity only, and forwards to the EventChannel as a positional list.
  - Traffic: each tick spawns `libxray.so api statsquery`, i.e. one process per second while connected.
  - Quick Settings tile (1.1.7 main) also runs in the daemon process.
  - Manifest declares READ_EXTERNAL_STORAGE, which is not needed.
- **iOS** (root package, Swift):
  - A gomobile XRay.xcframework (wrapper: Start/StartPrivate, Stop, SetAssetLocation, SetMemoryLimit = GC 10% + 30 MB, QueryStats; MeasureDelay is a STUB returning 0) plus HEV/Tun2SocksKit 5.15, both inside a Packet Tunnel extension.
  - The integrator must create a target named exactly "XrayTunnel" (bundle id = base + ".XrayTunnel", hardcoded suffix), share an App Group and a Keychain group (1.1.6+), target iOS 15+, and COPY the example PacketTunnelProvider.swift (1364 lines) into it.
  - Provider settings: remote 254.1.1.1; MTU 1500 (9000 in 1.0.x); IPv4 10.0.85.2/24 with default route; DNS 10.0.85.53 with matchDomains [""]; IPv6 captured and blocked (AAAA NODATA); server IPs excluded from routes.
  - Manager settings: includeAllNetworks=true, excludeLocalNetworks=false, APNs/cellular exclusions disabled. This is mandatory with no opt-out, and non-empty bypassSubnets are rejected. On-Demand Connect rule is used for recovery; explicit stop disables On Demand first.
  - Config is stored in a Keychain item, referenced from providerConfiguration. Before 1.1.6 it was plaintext Data in providerConfiguration.
  - Status/traffic: the app polls with a 1 s Timer using sendProviderMessage("xray_traffic"), which returns HEV counters. Delay uses "xray_delay<url>".
  - Proxy-only runs Xray inside the app process. Inference: it dies when the app is backgrounded.
- **macOS**: Packet Tunnel app extension (macOS 13+), plus a system-proxy proxy-only mode via networksetup. `dart run flutter_vless:setup_macos_vpn --bundle-id --group-id --team-id`. There is no documentation on Developer ID / System Extension distribution.
- **Windows**: xray.exe + tun2socks.exe + Wintun, IPv4-only VPN that needs admin. WFP filters act as a kill switch that survives app crashes; the admin must restart the app and press stop to clear them. Proxy-only edits the registry proxy. Stats come from the Xray gRPC Stats API. Standalone delay is unsupported and returns -1.

### A3. Dart API (main)
- `FlutterVless({onStatusChanged})`: callback only. No Stream and no getStatus()/current-state query.
- `initializeVless({notificationIconResourceType/Name, providerBundleIdentifier (base id), groupIdentifier, keychainAccessGroup?, options: VlessOptions?})`
- `requestPermission()` → bool
- `startVless({remark, config: Xray JSON string, notificationDisconnectButtonName, blockedApps, bypassSubnets, proxyOnly, geoAssetsDirectory, certificateAssetsDirectory, androidDnsPolicy{config, proxy}, androidDnsProxyOutboundTag, vpnRouting(sourceInboundIndex, defaultOutboundTag)})`
- `startVlessWithReport(...)` → VlessPreparationReport (closed codes). `stopVless()`.
- `getServerDelay({config, url = google generate_204})` → ms or -1. `getConnectedServerDelay({url})`.
- `getCoreVersion()`, `getProviderDebugSnapshot()`, `getCapabilities()`, `requestAddQuickTile()`, `clearQuickAccessProfile()`.
- Static `parse` / `parseMany` / `parseFromURL` → FlutterVlessURL (remark, getFullConfiguration, mutable maps). Typed XrayConfigDocument plus a validator.
- `VlessStatus{duration s, uploadSpeed, downloadSpeed, upload, download, state raw, connectionState connected|connecting|disconnected|disconnecting|unknown}`. It has no error or reason field.
- `VlessOptions`: Notification(icon, buttonLabel, action disconnect/openApp/none), QuickAccess(surface tile/menu/tray/Control Center, label, toggle/openApp, requireUnlock, icons), Reconnect(enabled, initialDelay, maxDelay, maxAttempts), Protection(killSwitch, onDemand, alwaysOn), Diagnostics(maxBytes/lines).
- Errors are PlatformException codes: INVALID_CONFIG (generic), INCOMPATIBLE_ROUTING, VPN_KEYCHAIN_ERROR, VPN_STOP_ERROR, VPN_START_CANCELLED. A Dart generation counter cancels superseded starts.

### A4. Configs and links
- Parsing is done in Dart into a full Xray JSON. Inputs: vmess/vless/trojan/ss/socks/hysteria2/hy2 links, raw Xray JSON or JSON array, base64 subscriptions, Clash YAML, sing-box JSON (WireGuard/Hysteria2 via YAML/sing-box). Unsupported protocols are skipped.
- The generated config is one socks inbound (HEV contract) + proxy outbound + direct + block, with empty routing.
- Native layers then rewrite the JSON heavily: injected auth SOCKS adapter, stats API, DNS outbound/rules, UDP/443 block (older macOS), private tags and ports.
- Known gaps:
  - Some ss:// variants don't work on iOS (#10, fork #18).
  - VLESS mlkem encryption is not representable in links; raw JSON is required.
  - Core rejects security=none + encryption=none to public hosts (#29).

### A5. Delay and traffic implementation
- **Android delay:** spawns a whole extra Xray process per test (temporary config + auth SOCKS) and retries 20×100 ms. It times ONE `HEAD` request, including SOCKS connect and TLS, as a single sample. Returns -1 on any error.
- **iOS delay:**
  - Connected: a Swift raw SOCKS5 + TLS + GET client inside the NE, 8–10 s timeout. Its TLS-1.2-only path returns -1 for TLS-1.3-only URLs.
  - Standalone: a second Go core in the app process, which returns -1 while proxy-only is active.
  - Older builds: logs show "XRay internal delay … 0ms" from the stub. UNVERIFIED whether 1.0.x getConnectedServerDelay returned 0.
- **Traffic:** speed = counter delta per 1 s tick. Upstream and fork reports: mostly 0 or jumpy (#86), cumulative values shown as speed (fork #14).

### A6. Example app
- Clipboard import, config preview/editor, routing editor (domain direct/proxy), proxy-only vs VPN toggle, counters, core version, blockedApps, Delay vs Profile delay, VPN Diagnostics, preparation report, Quick tile / menu / tray settings.
- The example hardcodes ids (dev.tfox.flutterXrayExample, group.dev.tfox.flutterXray), which users copied by mistake (#13).

## B. Issue catalogue (flutter_vless: all 28 issues and PRs read with comments)

### B1. Build and integration
- **#3** iOS, closed. "No such module 'XRay'". The xcframework had to be dragged into the pod target manually. Auto-download via SwiftPM/CocoaPods came in 1.0.5.
- **#5 and #6** iOS, closed (#6 filed by our user). SwiftCompile fails with an internal compiler error ("PHINode…", Swift 6.2.1 / Xcode 26.1.1) in the copied PacketTunnelProvider's `async startTunnel` with guard/fatalError and nested closures. Maintainer answered after five months ("see updated example").
  - Working fix from fork #3: use the completion-handler `startTunnel` and drop fatalError.
  - Required order: setTunnelNetworkSettings → wait → start core → wait for SOCKS → start tun2socks. Otherwise Safari shows "connection not private".
- **#7** iOS, closed. "Cycle inside Runner" when embedding the .appex. Fix (1.0.4 IOS_SETUP): move "Embed Foundation Extensions" below "Copy Bundle Resources".
- **#8** iOS, closed. How to build the xcframework → build_xray_ios.sh (gomobile).
- **#12** macOS/iOS 1.1.1, closed. SwiftPM can't resolve `.packages/flutter_vless_macos` / `../FlutterFramework`, which was missing from the published package. Fix: fallback package in 1.1.2. Workaround: use the Flutter-generated `.packages/flutter_vless-<ver>` path; deployment target ≥15.
- **#13** macOS 1.1.2, 30 comments, closed. `cannot find type XRayLoggerProtocol` because Swift sources and the bundled binary were out of sync.
  - Further hurdles in the same thread:
    - The prepare_apple_swiftpm.sh script was required.
    - The repo folder had to be named exactly `flutter_vless`, because SwiftPM takes package identity from the folder name.
    - Package.resolved PinsStorage v3 broke older Xcode, so they added Xcode 15 project files.
    - CLT-only installs fail.
  - Then the runtime didn't work. Cause: Runner and XrayTunnel need the same Team and App Group, and initializeVless needs the app's own base id, not the example's. Fixed in 1.1.3.
- **#14** Windows, closed 2026-09. generated_plugin_registrant includes `<flutter_vless_windows/flutter_vless_plugin.h>`, but the header lives under `flutter_vless/`. The workaround meant editing a generated file after every build. Fixed with a forwarding header (PR #27). Even after the workaround, the user said VPN mode "does not fulfill its main task".
- Fork-reported Android equivalents:
  - VPN fails only when installed from Google Play → useLegacyPackaging + extractNativeLibs (fork #4). Upstream #94/#116/#111/#72 and flutter_v2ray_client #21/#24 are the same: "connected, no internet" with minSdk ≥23, targetSdk 34 or Flutter >3.29.
  - Kotlin syntax errors shipped in a release (fork #6): no CI.

### B2. iOS "connected but no traffic" and status bugs
- **#4** closed without a fix. Shows connected, no traffic in either mode. A user switched to SwiftyXrayKit.
- **#10** wontfix. ss:// connects but carries no traffic (vmess works); "not all ss:// configs compatible". Same as fork #18 (CONNECTING → DISCONNECTED).
- **#20** closed, not a bug. Reality+Vision HTTP failed on macOS/iOS; the account was served different node keys. Its debug log reveals the 1.1.5 internals: QUIC (UDP/443) blocked to force TCP; KVC packetFlow fd read failing with a fallback to utun fd scanning; multiple health checks.
- Fork #10: status stuck CONNECTED with duration 0 after rapid connect/disconnect; stop doesn't help.
- Fork #13: WhatsApp doesn't work through the iOS tunnel (open).
- Fork #17: users can start the VPN from iOS Settings without the app.

### B3. Connection drops, reconnect, lifecycle
- **#17** iOS, filed by our user, closed. After a while (app in foreground or background) the tunnel either shows connected with no traffic, or disconnects entirely. Not present in the Dec-2025 build.
  - Causes: the HEV thread exits without cancelTunnel (zombie "connected"); HEV read-write-timeout of 60 s killed idle TCP; health check ran only once at start; sleep()/wake() were no-ops.
  - Fixed in a412b0026 / 1.1.5: exit detection → cancelTunnelWithError; periodic plus wake/path-change health checks; bounded logs. Timeout raised to 300 s. User confirmed on iOS.
- 1.1.6/1.1.7 changelog-only themes:
  - Distinguish manual system disconnect from failure.
  - Disable On Demand on user stop.
  - Serialize start/stop/permission and use provider reply deadlines.
  - Avoid signalling HEV after exit (shutdown hang).
  - Ignore events from earlier sessions.
  - Deliver status on the platform thread.
  - Cold Always-on restore.

### B4. Memory (iOS NE, 50 MB jetsam)
- **#23 and PR #24**, closed. Jetsam kill on Reality+XHTTP stream-up with many concurrent uploads.
  - Cause: the Go h2 client per-stream upload scratch buffer is min(server MAX_FRAME_SIZE, 512 KB). The Xray server advertises 1 MB, so 35–45 streams cost 18–23 MB.
  - On Go ≥1.25 x/net/http2 wraps the stdlib, so the fix is patching a GOROOT clone (`const max = 512<<10` → 128 KiB) before gomobile bind. Upstream XTLS/Xray-core#6663.
- Also: SetMemoryLimit uses GC 10% and a 30 MB limit. Bounded log rotation was added in 1.1.5 because extension I/O and memory grew unbounded.

### B5. Routing, per-app, bypass, geo, DNS
- **#15 and PR #18**, Android, closed. blockedApps accepted but never applied to the builder (lost in the Java→Kotlin rewrite; same as fork #7). Fixed 1.1.5.
- **#19** iOS, closed. Runtime-updatable geoip/geosite from the App Group. setenv(XRAY_LOCATION_ASSET) after Go init has no effect, so Xray looks only in the NE bundle. Added geoAssetsDirectory, which calls SetAssetLocation inside Go.
  - Fork #15 (Android): copyAssets overwrote custom .dat on every connect, and Xray crashes if a referenced category is missing.
- **DNS history:**
  - The 1.0.x provider hardcoded 8.8.8.8 + 114.114.114.114, a Chinese resolver.
  - 1.1.6 routes DNS through the proxy with a virtual resolver and no physical fallback. Android has a DNS policy option (config vs proxy).
  - IPv6 is blocked everywhere with AAAA NODATA; the 1.1.7 changelog says "IPv6 payload captured", but forwarding is still IPv4-only on Apple and Windows.
- bypassSubnets: rejected on iOS VPN; converted to Xray direct rules on macOS/Windows.

### B6. Config, link parsing, core validation
- **#29** Android, closed. INVALID_CONFIG for streamSettings.security none, because Xray 26.9.9 rejects VLESS to a public address without TLS/Reality or VLESS encryption. The plugin's generic message hid the core's actual reason.
- **#10**: see B2.
- 1.0.5 notes: flat VLESS normalization; port conflict auto-handling; log path sanitization; "avoid reporting connected when core exits immediately". Fork #16 also reports that Android startVless always succeeds even if Xray fails.

### B7. Desktop runtime
- **#15** Windows. VPN mode flashed several CMD windows (route/netsh via shell), then either stalled or showed a runaway upload counter (a loop). A reboot fixed it. Later reworked: absolute exe paths, no shell, owned job objects, WFP kill switch, interface binding.
- 1.1.0: macOS system proxy has no UDP support, so QUIC breaks; proxy settings are restored on exit.

### B8. Feature requests
- Desktop (#1, #9: delivered 1.1.0).
- WireGuard (#16: 1.1.3).
- Linux (#25: open).
- Quick Settings tile (#22 and PR #21: still open after review). Reviewer blockers:
  - Android 14 `TileService.startActivityAndCollapse(Intent)` throws for targetSdk 34+; use the PendingIntent overload.
  - Don't request VPN consent for proxy-only.
  - Tile state goes stale when the engine is dead; persist state in the VPN process and call requestListeningState.
  - The maintainer then wrote his own tile implementation.
- Dynamic geo files (#19: done).

### B9. License
- flutter_vless's maintainer forced fork flutter_v2ray_plus to add MIT attribution (fork #2).
- NOTICE/TRADEMARKS demand that notices are preserved.

### B10. Process
- Long silences (Dec–May).
- "Fixed on main, pub later" (#17 user asked when).
- Pub 1.1.7 packages don't match main.
- Binaries are versioned separately (Maven, GitHub releases, user-supplied exe) and drift from wrappers (#13).
- Every native fix requires integrators to re-copy provider files.

### Upstream and forks (blueboy-tm/flutter_v2ray, 115 items; amir-zr/flutter_v2ray_client; shafiquecbl/flutter_v2ray_plus)
- **Android lifecycle crashes:**
  - Null Intent in onStartCommand on sticky restart (#103).
  - BackgroundServiceStartNotAllowedException when stopping via startService from the background (#66).
  - ANR when notifications are blocked (#107).
  - ANR "startForegroundService did not call startForeground" (client #22).
  - NPE in onActivityResult with a null pending result (#98).
  - requestPermission returned false without waiting for the user (#77).
  - registerReceiver missing the EXPORTED flag on API 34 (#50).
  - IntentReceiverLeaked when the app is killed (client #23).
  - Disconnects after 3–20 s (#24/#26/#30, client #21/#19).
  - Rapid start/stop breaks stop (#33).
  - Slowdown 15 min after the app is terminated (#47).
- **Packaging:**
  - Executables not extracted (above).
  - 16 KB page-size requirement from Google Play (#115/#119/#120).
  - Duplicate libgojni.so when combined with other gomobile plugins (#118).
  - Play Protect flags the APK (#121).
  - SELinux denial for the tun2socks executable on Vivo kills VoIP UDP (client #33).
- **Status and stats:**
  - No initial status until connected (#90).
  - Speed mostly 0 (#86) or stuck at 0 (#67; client #15: core built without stats).
  - Proxy-only shows zero traffic (#6).
  - Reset counters on disconnect (#7).
- **Delay:**
  - Blocks or crashes while connected (#8, #78).
  - Users want batch ping of many configs concurrently, like v2rayNG (#78).
- **Network:**
  - YouTube over Wi-Fi / IPv6 / Irancell problems (#15/#18/#43; DNS fix).
  - Release build gets no internet without a LAN bypass (#64).
- **Requests:**
  - Notification customization or disabling (#22/#23/#37/#101, speed shown in the notification).
  - QS tile (#36).
  - Per-app include/exclude (#34/#36/#95).
  - Routing, geoip/geosite, LAN/mainland bypass (#11/#29/#57/#80/#83).
  - DoH (#60), fragment (#49), balancer (#109), hysteria (#63).
  - Prompt core updates (#70/#91/#106).
  - Hotspot sharing (#79).
  - Background state/data monitoring with the app closed (#105).
  - Core log access (client #3).
  - iOS and desktop support were the most requested items (about 12 issues).

## C. Lessons for our sing-box/libbox plugin (prioritized)

### P0 — architecture
1. **Run the core in-process (libbox gomobile AAR / Libbox.xcframework in the NE). Never exec binaries.** Feed the TUN fd directly through the libbox PlatformInterface (OpenTun/TunOptions). This removes the whole #1 failure class (useLegacyPackaging, AAB installs, minSdk ≥23, SELinux, Play Protect), the tun2socks/HEV layer and its bugs (#17), and per-second stats processes. It also removes the local SOCKS adapter.
   - Pitfall: if any mixed/socks inbound exists in VPN mode, require auth or bind privately. flutter_vless 1.1.6 had to add auth because other apps could use the open localhost proxy.
2. **Ship the Apple provider as a library class.** For example, an `open class` in a SwiftPM/CocoaPods product that the integrator subclasses in about 3 lines, never a copied 1300-line file.
   - Version-lock binaries with wrapper code in one release, with checksums. Avoid #13-style skew.
   - Make the extension bundle id fully configurable (no hardcoded ".XrayTunnel").
   - Provide a setup CLI: target, entitlements, App Group, embed-phase order (avoid the #7 build cycle), deployment targets.
   - Run a runtime self-check that reports mismatched Team, App Group or bundle id as typed errors.
3. **Truthful state.**
   - `start()` resolves only after libbox has started and the TUN is up, or throws a typed error carrying the core's message (sing-box CheckConfig/start error text). No generic INVALID_CONFIG (#29) and no success-on-failure (fork #16).
   - Expose `checkConfig()`.
   - Status = Stream + `getStatus()`, with an initial emit on subscribe (#90). States: connecting, connected, reasserting/recovering, disconnecting, disconnected, plus a lastError (code + message) and a stop reason (user / system / error / revoked).
4. **Use the libbox CommandServer/CommandClient (unix socket in the app data dir / App Group) for status, traffic, logs, connections, groups and URL tests.**
   - This works across the Android `:service` process and the iOS NE, needs no Activity-scoped receivers (IntentReceiverLeaked, RECEIVER_NOT_EXPORTED) and no 1 s provider-message polling.
   - Report traffic as rates over real time deltas plus totals (#86, fork #14), reset per session (#7), and expose the libbox memory/goroutine/connection counts.
5. **Serialize start/stop/restart in native code** (single queue + generation tokens). Make them idempotent, with deadlines on provider IPC. Avoid stuck CONNECTED after rapid toggles (upstream #33, fork #10).
6. **Licensing:** sing-box is GPL-3.0-or-later with an extra name-use term. A plugin bundling libbox inherits GPL obligations: App Store + GPL tension, and we cannot use the "sing-box" name to imply association. Xray is MPL-2.0, which is why flutter_vless is MIT. Decide the license up front. If we reuse any flutter_vless parsers, keep their MIT notice; they enforce attribution (fork #2).

### P1 — Android specifics
1. Call startForeground immediately in onStartCommand, even without POST_NOTIFICATIONS (#107, client #22).
   - Handle a null Intent (sticky restart or Always-on start without the app, #103). Restore the last authorized profile from encrypted storage.
   - Stop via a binder/in-process command, not startService from the background (#66).
   - Make the VPN-permission flow lifecycle-safe (#98, #77).
2. FGS type: flutter_vless uses specialUse/"vpn". Decide between specialUse and systemExempted and verify against the Play FGS policy. UNVERIFIED which one SFA uses; check the sing-box-for-android manifest.
3. Per-app: support both include and exclude modes, mapped to libbox TunOptions include/exclude packages. Add a test that the Builder actually receives them (#15/#18/fork #7). Don't exclude our own UID by default; libbox protects its own sockets (autoDetectInterfaceControl → VpnService.protect).
4. Implement the DefaultNetworkMonitor / setUnderlyingNetworks properly. Don't hardcode setMetered(false), which flutter_vless does unconditionally and which mislabels cellular as unmetered. React to network changes (libbox resets the network).
5. Always-on / lockdown: declare SUPPORTS_ALWAYS_ON, hide Disconnect under lockdown, expose isAlwaysOn/isLockdown capability.
6. Notification: fully customizable title, text, icon, channel name, button label/action, optional live speed. Also allow opting out of the plugin's content or supplying your own (#37/#101).
7. Quick Settings tile: optional. Use the PendingIntent startActivityAndCollapse on API 34+. No consent prompt for proxy-only. Persist tile state from the service process and call requestListeningState (PR #21 review).
8. Packaging:
   - Verify 16 KB alignment of libbox .so (Play requirement).
   - libbox's gomobile output is libgojni.so, which collides with other gomobile AARs (#118). Check whether the SagerNet gomobile fork can rename the library (UNVERIFIED).
   - Declare no superfluous permissions (flutter_vless declares READ_EXTERNAL_STORAGE).

### P1 — iOS/macOS specifics
1. Memory (50 MB NE):
   - Use the libbox memory-limit mode (LibboxSetMemoryLimit) and bounded logs/rotation.
   - Audit Go h2 client transports (sing-box HTTP/gRPC v2ray transports) for the #23 scratch-buffer pattern. UNVERIFIED whether sing-box 1.14 hits it.
   - Test with connection-heavy apps (speedtest, banking).
2. Provider robustness:
   - When the core dies, call cancelTunnelWithError; no zombies (#17).
   - Handle wake() and path changes by resetting connections.
   - Bound IPC replies.
   - Prefer the completion-handler startTunnel (the Swift 6.2 ICE in #5/#6). Compile the provider in CI on the latest Xcode.
   - Apply network settings before starting traffic (fork #3).
3. includeAllNetworks, excludeLocalNetworks, excludeAPNs, excludeCellularServices, enforceRoutes and On Demand must be **options** with documented trade-offs. flutter_vless forced includeAllNetworks=true with all exclusions disabled. That blocks LAN and has full-device-outage risk when the provider dies. Possibly relevant to the WhatsApp/push issues (fork #13; UNVERIFIED).
   - Disable On Demand on user stop.
   - Optional: refuse provider starts not initiated by the app ("prevent connect from Settings", fork #17; idea: inspect startTunnel options, UNVERIFIED).
4. DNS: never hardcode public resolvers (the 1.0.x template had 114.114.114.114). Use the sing-box TUN DNS address + hijack-dns. Make IPv6 configurable instead of hard-blocking: sing-box TUN supports IPv6 natively, and IPv6 problems were common upstream.
5. Shared data:
   - Call LibboxSetup(basePath/workingPath/tempPath in the App Group) before any Go use. Lesson from #19: env set after Go init is ignored.
   - Rule-sets (.srs) local/remote with update interval replace geoip/geosite .dat updating.
   - Store the config in the App Group (file protection) or the Keychain with AfterFirstUnlock (flutter_vless VPN_KEYCHAIN_ERROR before first unlock). Not plaintext in providerConfiguration.
6. Check fd acquisition: libbox gets the utun fd by scanning descriptors (the method flutter_vless dropped on macOS in favour of NEPacketTunnelFlow + socketpair). It is used by the official sing-box app, but test it on each iOS/macOS version.
7. Proxy-only on iOS runs in the app process. Document that it stops in the background, or don't offer it.
8. macOS: decide app-extension (App Store) vs System Extension (Developer ID) distribution; flutter_vless has no guidance. Document Team/App Group consistency checks (#13).

### P1 — delay/ping
1. Use libbox URL test on the running instance (urltest/selector groups, concurrent, streamed per outbound).
2. For not-running profiles, provide a batch API with a concurrency limit, per-item timeout and results streamed as they arrive. This was the main v2rayNG-style request (#78).
3. Return a typed result (ms | timeout | dns | tls | refused | unsupported), never a bare -1 or a stub 0.
4. Make the URL configurable (default gstatic generate_204). Document what is measured (handshake vs. warmed second request); consider several samples.
5. Never block the UI thread or crash while connected (#8).
6. Must work while the VPN is up; flutter_vless needed workarounds for listener-port clashes.

### P2 — config and links
1. Provide link → sing-box outbound conversion with real-world test corpora: vless (reality, vision, ws/grpc/httpupgrade/http), vmess, trojan, ss (SIP002 + legacy base64 + plugins; #10 and fork #18 show ss breakage), socks, hysteria2/hy2, tuic, wireguard. Also base64 subscriptions, Clash YAML and native sing-box JSON.
2. **Gap to flag:** flutter_vless users rely on Xray-only features: XHTTP/SplitHTTP (in #20 and #23), VLESS mlkem encryption, raw Xray JSON. sing-box can't run these. Fail clearly with "unsupported transport/feature" instead of producing broken configs.
3. Keep raw-config passthrough for advanced users and expose the libbox format/check.

### P2 — process and quality
- CI that builds the example and a fresh `flutter create` consumer using the published artifacts on every platform. Bugs that slipped through without it: #12, #13, #14, fork #6.
- Device test matrix.
- Prompt releases to pub after fixes.
- A changelog that flags required integrator actions.
- Keep docs for Play/App Store review: VPN disclosure, privacy policy, Play FGS declaration (UNVERIFIED specifics), Apple NE entitlement.

### Features flutter_vless / flutter_v2ray users requested that we should support
1. Android + iOS + macOS + Windows, and Linux (#25).
2. VPN mode and proxy-only mode (with LAN-share/hotspot option, #79).
3. Protocols: VLESS-Reality/Vision, VMess, Trojan, SS (incl. SS2022), SOCKS, Hysteria2, WireGuard, TUIC (plus clear handling of XHTTP).
4. Import: share links, base64 subscriptions (with update), Clash YAML, sing-box JSON.
5. Per-app include/exclude.
6. Domain/IP/geo/rule-set routing, LAN/private bypass, runtime-updatable rule data.
7. Custom DNS incl. DoH/DoT, FakeIP; no DNS leaks.
8. IPv6 support.
9. Kill switch / Always-on / On-Demand / auto-reconnect with backoff.
10. Status stream + getStatus + error reasons.
11. Live speed + totals, also when the app was closed (#105).
12. Ping: connected, per profile, and batch.
13. Core version.
14. Core/provider logs with redaction (client #3, getProviderDebugSnapshot).
15. Customizable notification incl. speed and actions.
16. Android Quick Settings tile / iOS Control Center / desktop tray.
17. Balancer/auto-select (urltest), TLS fragment (#49; sing-box tls fragment support UNVERIFIED for 1.14).
18. Working VoIP/UDP (WhatsApp, Telegram calls).
19. Option to prevent start from iOS Settings.

## Coverage check by lead (2026-10-27, after the agent was cut off by the usage limit)
- GitHub tracker re-listed via API: 28 items (#1–#27, #29; #28 does not exist). Every one is covered above.
- GitHub Discussions: enabled, 0 discussions.
- Upstream flutter_v2ray (115 items) and forks flutter_v2ray_client / flutter_v2ray_plus: covered above.
- main-branch CHANGELOG 1.1.7 (unreleased train) re-read. Additional lessons not listed in C:
  - Validate a new config before replacing a working session; keep the old one if the new start fails.
  - Ignore native events from an earlier session (session/generation id), including network callbacks queued before Stop.
  - Cancel pending/superseded starts on Stop or a newer Start (fixed error code, no private details).
  - Preserve unknown JSON fields at every depth when patching user configs; never normalise away caller data.
  - Single monotonic deadline for watchdog/health probes; cancel probes on session end.
  - Reset speed baselines across gaps/restarts (no spikes after reconnect).
  - CI: 16 KiB ELF checks for Android runtimes; real traffic tests in an emulator and on a physical iPhone.
