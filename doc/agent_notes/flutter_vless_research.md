# flutter_vless research (for our sing-box/libbox Flutter plugin)

Status: IN PROGRESS (research agent, 2026-10-27). Sections appended incrementally.

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
