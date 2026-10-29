---
name: roadmap
description: "Full improvement plan for sing_box after 1.0.0 (R0-R15): R0-R6 + R14 fixes DONE and pushed; next R7; per-task plans and findings"
metadata:
  node_type: memory
  type: project
  originSessionId: 7f1b09fa-8e64-4857-9853-99d9ed357c4c
  modified: 2026-10-29T20:30:00.000Z
---

Plan made 2026-10-28 from the user's list and the competitor study (`competitor-analysis.ru.md` in worktree
`flutter-singbox-competitor-analysis-b4d5cd`, untracked). The user starts a task with "начни задачу Rn".
Rules: work in branch `release-1.1.0`, NOT a branch per task ([[feedback-one-release-branch]]), commit after each finished piece, no co-author trailer, never push
([[feedback-commits-and-push]]); no subagents ([[feedback-no-subagents]]); talk Russian. **Network may be tight: ask
before any download** (SDKs, Gradle/CocoaPods/SwiftPM deps, git clones, release assets). Offline is fine:
`flutter pub get --offline`; pub cache already has `yaml` 3.1.4, `http` 1.6.0, `pana` 0.23.19.
Every config change: `sing-box check` tests with `SING_BOX_BIN` (CONTRIBUTING.md). "VERIFY" = check first, unconfirmed.

Status/queue: see [[navigator]] (start there). R0-R6 DONE and R14 audit + main fixes DONE (2026-10-29), all pushed
(release-1.1.0 = fb4e5b1, CI run 40914059314 green). NEXT: R7.
Order: R0 → D1 (lx API design: DECIDED = option A, see R8) → R4 → R5 → R6 → R7 → R14 (audit vs SFA/SFI/desktop,
its fixes) → R8 → R13 (protocol matrix, both cores) → R15 (deps) → R9 (README/pub.dev, uses R13 tables) → R10-R12.
Versions: the user wants R4 (and following tasks) in the 1.1.0 update too, on branch release-1.1.0 (2026-10-29).
R4 design chosen by the user 2026-10-29: `mode` = what happens to unmatched traffic (`proxyAll` default |
`proxyListed`), lists stay independent and work in every mode: `bypassCountries` unchanged (1.1.0 compatible), new
`blockedInCountries` (country's blocked lists → proxy), `proxyDomains`/`proxySubnets`; rule order block → proxy lists →
bypass → final. No `direct` mode (Clash `Direct` exists). Network allowed for verifying rule-set URLs.

## R0. Finish "lower min Flutter" — DONE (CI verified 2026-10-28/29)
See [[lower-min-flutter]]: verify builds on Flutter 3.47 and 3.29.3, add a CI job that builds a fresh
`flutter create` app (3.29.3, minSdk 24) depending on the plugin by path (Android + iOS CocoaPods), drop "WIP".

## R1. IP version mode — DONE (7bedc06)
`enum SingBoxIpVersion { ipv4, ipv6, dual }` + `bool preferIpv6` for dual; field in `SingBoxConfigOptions`
(`lib/src/config/config_options.dart`) and persisted via `SingBoxSettings` (`keyIpVersion`) so auto connect/boot use it.
Mapping in `config_builder.dart` (today `tun.enableIpv6` + `dns.strategy`, ~line 427):
- ipv4: TUN keeps the IPv6 address so v6 traffic is captured, route rule `ip_version: 6 → reject` (no IPv6 leak),
  DNS + `default_domain_resolver` strategy `ipv4_only`, fakeip without inet6.
- ipv6: strategy `ipv6_only` (sites without AAAA fail - document).
- dual: both addresses, strategy prefer_ipv4 / prefer_ipv6.
Keep `enableIpv6`/`strategy` working (explicit values win; document precedence). Tests + sing-box check; example
Routing page selector; README section.

## R2. Subscriptions by URL — DONE (1f58da7; background updates still R12)
New model `SingBoxSubscription {id, name, url, userAgent, updateInterval, autoUpdate, lastUpdated, lastError,
upload, download, total, expire, webPageUrl, supportUrl, announce, serverCount}`, stored natively (storage key
`subscriptions`, like servers); servers already have `subscriptionId` (`lib/src/models/server_config.dart`).
API on `SingBox`: `addSubscription(url, {name, userAgent, updateInterval})`, `updateSubscription(id)`,
`updateSubscriptions({bool onlyStale = true})`, `removeSubscription(id, {removeServers = true})`, `getSubscriptions()`,
`watchSubscriptions()`. Fetch with `dart:io` HttpClient (no new dependency): redirects, timeout, gzip, default UA
`sing-box/<core version>` (configurable; providers pick the format by UA). Parse headers:
`subscription-userinfo` (upload/download/total/expire), `profile-title` (plain or `base64:`), `content-disposition`
filename, `profile-update-interval` (hours), `profile-web-page-url`, `support-url`, `announce` (base64 allowed).
Body → existing `SingBoxShareLink.parseSubscription` (+ R3 YAML; sing-box JSON full configs: take outbounds).
Update = replace that subscription's servers, keep ids by tag so the active server survives. Auto update stale ones in
`initialize()` and on app resume (`autoUpdate`); true background update (WorkManager/BGTask) = R12.
Errors → `SingBoxSubscriptionException` (HTTP code, empty, unparsable). Tests with a local `HttpServer`.

## R3. Clash / mihomo YAML subscriptions — DONE (49681b2; proxy-groups import not done)
Add `yaml: ^3.1.2` (cached). New `lib/src/config/internal/clash.dart`: detect YAML (`proxies:` key), map each
`proxies` entry to a sing-box outbound: ss (+ obfs / v2ray-plugin / shadow-tls opts), vmess, vless (flow,
`reality-opts`, `client-fingerprint` → utls), trojan, hysteria, hysteria2 (ports hopping, obfs, up/down), tuic v5,
wireguard (ip/ipv6/keys/reserved/mtu → endpoint), socks5, http(s), anytls, ssh; transports `network` ws/grpc/h2/http/
httpupgrade with `*-opts` (ws early data, headers Host); `tls`, `sni`/`servername`, `skip-cert-verify`, `alpn`.
Unsupported (snell VERIFY, mieru, xhttp unless R8 lx core) → skip with a reason list returned to the caller
(`SingBoxImportResult {servers, skipped: [(name, reason)]}`). Optional: `proxy-groups` → selector/urltest groups.
Ignore Clash `rules`/`dns` (our routing). flutter_sing_box 3.0.3 `ClashProvider` (GPL-3.0) is a field-mapping reference.
Fixtures for every type, all validated by sing-box check.

## R4. Built-in routing — DONE 2026-10-29 (7e39ae9, 517aef5, e8a017b, 5ff09e0; design changed, see top)
Facts found: `sing-box check`/start FAIL on a missing local rule-set file; `.srs` starts with "SRS"+version byte
(`sing-box rule-set compile` makes fixtures; test fixture `test/config/support/example.srs`); runetfreedom
`release` branch has `sing-box/rule-set-{geosite,geoip}/{geosite-ru-blocked (550 KB), geoip-ru-blocked (200 KB),
geosite-ru-available-only-inside}.srs` (+ `geosite-ru-blocked-all` 9.8 MB, too big), GPL-3.0; SagerNet has NO
`geosite-gfw` (cn preset = `geosite-geolocation-!cn`); jsDelivr `cdn.jsdelivr.net/gh/<o>/<r>@<branch>/<path>` works;
`sing-snell` is in the Go module cache → sing-box 1.14 likely has snell (open check). Dart pitfall:
`whenComplete(() => map.remove(k))` returning the same future deadlocks. Not done: Clash `proxy-groups`, IR preset.
Old plan below. Today: `SingBoxRoutingRules` (bypass/blocked/proxy apps, domains, subnets, bypassLan, bypassCountries via geoip/geosite
rule-sets, blockAds, dnsServers) in `lib/src/config/routing_rules.dart`, `rule_sets.dart`.
- R4a Modes: `SingBoxRoutingMode { global, bypassCountries, proxyListed, direct }`. `proxyListed` = only listed
  (blocked) resources via proxy, the rest direct; presets per country, e.g. RU: direct `geoip-ru` +
  `geosite-category-ru`, proxy list from runetfreedom/russia-v2ray-rules-dat (sing-box rule-sets) (URLs VERIFY);
  CN, IR similar. Rule-set URLs configurable, mirrors (jsDelivr / GitHub raw), `download_detour` direct or proxy.
- R4b Custom ordered rules: `SingBoxRoutingRule {domains, domainSuffixes, keywords, regexes, ipCidrs, ports,
  packages (Android), ruleSets, network tcp/udp, protocols (quic, bittorrent), action proxy|direct|block, outbound}`
  → sing-box route rules + matching DNS rules (direct domains resolved by the local DNS). JSON import/export.
  Toggles: block QUIC, BitTorrent direct.
- R4c Rule-set manager: a failed initial remote rule-set download aborts the start (known sing-box fact), so the
  plugin downloads `.srs` itself (Dart HttpClient, retries, mirrors) into the working dir, refers to them as `local`
  rule-sets, refreshes them periodically and before connect if missing; API `updateRuleSets()`, status stream.
  Android and iOS paths: rule-set files must be in the shared dir (iOS app group, `SingBoxPaths`).
Example app Routing page; README section.

## R5. Four ping methods — DONE 2026-10-29 (3698bea…a6c74da; probe address later changed to 198.51.100.1, see navigator)
DECIDED 2026-10-29 (user): connected proxy ping WITHOUT a local port (option B): generated/applied configs get rules
`{ip_cidr: <TUN peer addr, e.g. 172.19.0.2/32>, port: 20000+i, outbound: tag_i, override_address/port: urlTestUrl
host:port}` right after sniff/hijack-dns; Dart connects raw to that addr:port (+TLS SNI = url host). Fallback: libbox
urlTest (HEAD) when the app is not in the tunnel / rules absent. Disconnected: probe core = 2nd libbox CommandServer
WITHOUT Start() (no socket) + StartOrReloadService(probe config: mixed 127.0.0.1 + auth users per tag, no TUN/cache/
clash api). VERIFIED: sing-box urltest = HEAD, timer from after dial; libbox 1.14 has only CommandServer (no
standalone API); route action has override_address/override_port; sing-box 1.14 has snell. iOS has an app→extension
message channel (handleAppMessage) for tcp/icmp while connected.
Today `SingBoxPingMethod {urlTest, tcp}` (`lib/src/models/ping_result.dart`); `pingOutbound` = libbox `urlTest`
through a urltest group (only while connected); `_tcpPing` = dart:io Socket (goes INTO the tunnel when connected).
New `SingBoxPingMethod { proxyGet, proxyHead, tcp, icmp }` (`urlTest` deprecated alias), `ping(server, {method, url,
timeout})`, `pingServers(..., method)`, `pingOutbound(tag, {method})`; result gets `method`, `url`, `statusCode`.
- proxyGet/proxyHead: generated (and applied) configs get a hidden `mixed` inbound `probe-in` on 127.0.0.1:<random>
  with one user per outbound (random password) and first route rule `inbound probe-in + auth_user → outbound tag`;
  Dart HttpClient with proxy + credentials does GET/HEAD to `urlTestUrl`, measures time to response headers.
  VERIFY which method libbox urlTest uses (sing-box `common/urltest/urltest.go`). VERIFY on iOS that the app reaches
  the extension's 127.0.0.1 listener.
- Not connected: start a temporary no-TUN core ("probe instance": only probe-in + outbounds + DNS) in the app process
  — RESEARCH libbox 1.14 API for a second/standalone service (Android: not inside the VpnService command server).
  This also gives real latency for UDP protocols (hysteria2/tuic/wireguard) that TCP ping cannot measure.
- tcp / icmp natively (new channel methods): resolve the server via the underlying network, not the tunnel (fake-ip!):
  Android: socket on the default `Network` (`DefaultNetworkMonitor`) or `VpnService.protect`; ICMP via
  `Os.socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP)` ping sockets (ICMPv6 for v6). iOS: in-app when disconnected; when the
  tunnel is up, run in the extension via `sendProviderMessage` (provider sockets bypass the tunnel); ICMP via
  `socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP)` (SimplePing style). Clear errors ("no ICMP reply", "UDP-only protocol").
Update doc/platform_channel.md (contract first), both platforms, fake platform, e2e (local server has
`www/probe.txt`), example Tools page.

## R6. iOS without CocoaPods — DONE 2026-10-29 (fb4e5b1): option (b) works = link via Flutter's generated package; `dart run sing_box:setup_ios`
Plugin already supports SwiftPM, but the Packet Tunnel extension links `pod 'SingBoxTunnel'`
(`ios/scripts/add_packet_tunnel.rb` ~line 251) and the script needs the `xcodeproj` gem (CocoaPods). Goal: zero
CocoaPods. Options to test:
(a) extension links product `SingBoxTunnel` of the SAME local package Flutter references
(`ios/Flutter/ephemeral/Packages/.packages/<plugin folder>`; folder name differs for pub cache vs path deps — VERIFY;
path changes on upgrade → re-run script);
(b) link the product transitively through Flutter's `FlutterGeneratedPluginSwiftPackage` reference;
(c) compile `SingBoxTunnel` sources + Libbox.xcframework into the extension directly.
Then replace the Ruby script by `dart run sing_box:setup_ios` (edits pbxproj like flutter_tools does; no gems), keep
the Ruby one for CocoaPods apps. Also VERIFY the Package.swift `Context.packageDirectory` FlutterFramework check
(R0). Docs: "no Podfile needed on Flutter 3.44+".

## R7. Engine options from competitors (medium, native) — NEXT
Also from the R14 audit: Android `setSystemProxyEnabled` is a no-op and `getSystemProxyStatus` reports enabled =
available; SFA persists a "system proxy" switch and reloads. OOM options: SetupOptions `oomKillerEnabled`,
`oomKillerDisabled`, `oomMemoryLimit` (bytes; on iOS 0 = default NE limit) - Android hardcodes off in
LibboxRuntime.kt, iOS uses `disableMemoryLimit` start option.
Android proxy-only mode (foreground service `specialUse`, no VpnService, mixed inbound, no VPN permission);
system HTTP proxy in VPN mode (tun `platform.http_proxy` → `VpnService.Builder.setHttpProxy`, Android 10+);
`allowBypass`; core memory limit option (libbox SetupOptions / oom fields, VERIFY names) for both platforms.
Settings + docs; iOS: document what is impossible (proxy-only needs the app alive).

## R8. Core choice: sing-box or sing-box-lx (large; needs network)
sing-box-lx (github.com/Leadaxe/sing-box-lx): thin fork, client extras each behind a build tag: XHTTP transport,
AmneziaWG 3.x, MASQUE, TrustTunnel, SSL VPN, observability (CommandClient), round-robin balancing; rebased on
upstream tags. VERIFY first: license (GPL?), tag scheme, build tag names, outbound JSON for each feature, libbox
(gomobile) builds, iOS extension memory (~50 MB) with extras.
Design: build-time choice (both export the same libbox classes, one per app):
- one switch in the APP's pubspec.yaml: `sing_box: {core: lx}` (default `standard`) + env `SING_BOX_CORE` override;
  read by Gradle (`rootProject.projectDir/../pubspec.yaml`), the podspec (`Dir.pwd/../pubspec.yaml` during
  pod install) and Package.swift (walk up from `Context.packageDirectory`, same assumption as R0 - VERIFY).
- `LIBBOX_LX_VERSION`, release `libbox-lx-v<version>` with `libbox.aar` + `Libbox.xcframework.zip`, sha256 pinned
  in `android/libbox.properties` (lx.* keys), Package.swift (`let libboxLx...`), `ios/libbox.rb`;
  `scripts/build_libbox.sh --core lx`, `release_libbox.sh`/`verify_libbox_release.sh` for both; CI matrix.
- Runtime: `SingBoxRuntimeInfo.core` + feature set; link parser accepts lx-only formats (vless `type=xhttp`,
  AmneziaWG params Jc/Jmin/Jmax/S1/S2/H1-H4, MASQUE, TrustTunnel, SSL VPN) and fails with "requires the
  sing-box-lx core" on the standard core; `connectToServers(strategy: urlTest | roundRobin)`; extra observability
  streams if the CommandClient API allows. README core comparison table.
- **API design D1 = option A, chosen by the user 2026-10-29** (over B "one SingBox + supports()" and the hybrid C
  `SingBox.instance.extended`). `class SingBoxExtended extends SingBox` holds every lx-only member:
  - ONE object: the static singleton is always created as `SingBoxExtended`; `SingBox.instance` returns it typed as
    `SingBox`, `SingBoxExtended.instance` as `SingBoxExtended` (otherwise the first caller fixes the type). The
    subclass needs the private `SingBox._()` → same library (same file or `part`) or an `@internal` constructor.
  - Overrides add optional named params (valid Dart override), e.g. `connectToServers(..., {SingBoxGroupStrategy
    strategy = urlTest})` with `roundRobin` only there; new streams/methods (observability) only there.
  - Each lx-only member checks the running core (from `initialize()`) and throws the EXISTING
    `SingBoxUnsupportedException('requires the sing-box-lx core')` (no new exception type); base `SingBox` exposes
    `core` / `supports(feature)` so standard apps can query too.
  - Config layer (same for any option): parsers/builders take optional `SingBoxCoreFeatures features`, default =
    running core after `initialize()`, standard before it; lx-only links fail / subscriptions skip them with
    "requires the sing-box-lx core"; stored lx-only servers stay, `connectToServers` skips them, `connect` throws.
  - Docs: README "sing-box-lx core" section shows `SingBoxExtended.instance`; dartdoc says which members need lx.

## R9. pub.dev presentation (medium; after features)
Facts (verified in pana 0.23.19 source): the Example tab shows `example/README.md` first (then `example/example.md`,
`example/lib/main.dart`, ...); pubspec `screenshots:` gallery, each file ≤ 4 MB (png/webp/gif). The Installing tab is
generated by pub.dev and cannot be customized → put the "Quick start" into `example/README.md` (Example tab) and at
the top of README.
- README ORDER required by the user (2026-10-29): badges + one-line pitch → (1) protocol comparison table at the
  very top: protocol/transport × sing-box core × sing-box-lx core (✓ / ✗ / requires lx), filled from R13 results
  only (verified, not guessed) → (2) platform support table: Android ✓, iOS ✓, macOS / Windows / Linux "in
  development" → (3) all package features, nicely written (grouped, short, scannable) → (4) installation, quick
  start, platform setup (`<details>`), examples, topic docs (connect, servers & subscriptions, routing, ping & tests,
  settings, errors), FAQ/troubleshooting, migration, license → (5) LAST: support section ("Buy Me a Coffee"-style
  badge/link; ask the user for the actual link/platform before writing).
- pubspec `topics:` — pub.dev allows at most 5 (now: vpn, proxy, sing-box, vless, network). Pick the 5 best by
  search value (candidates: vpn, proxy, sing-box, vless, xray, shadowsocks, network, tunnel, privacy); VERIFY the
  limit/format in pana/pub docs before editing. Also tune `description` (60-180 chars) for search.
- `example/README.md` = Quick start (copy-paste app) + what the full example shows.
- API docs: `dartdoc_options.yaml` with categories (Connection, Servers & subscriptions, Routing, Diagnostics,
  Settings, Config toolkit, Models, Errors) and topic pages `doc/topics/*.md`; `{@category}` on public symbols;
  library doc in `lib/sing_box.dart` with snippets.
- `screenshots:` 4-5 webp captured from the example app (emulator/simulator, no download).
- Check pana locally (160/160) and `flutter pub publish --dry-run`.

## R13. Protocol matrix: verify every protocol, both cores (large; after R8; feeds R9 README tables)
Standard core: list every outbound/endpoint type sing-box 1.14.4 supports (from `option/` and `protocol/` in the
v1.14.4 sources: vless, vmess, trojan, shadowsocks (+2022, plugins), shadowtls, hysteria, hysteria2, tuic, anytls,
wireguard, socks, http, ssh, naive, tor, snell?, ... VERIFY each) and every transport (ws, grpc, http/h2,
httpupgrade, quic) + TLS/Reality/uTLS. For each: share link parse/export, Clash import, `sing-box check`, and a REAL
e2e connection on the Android emulator against a local sing-box server inbound (extend
`example/integration_test/server/server.json` with one inbound per protocol; self-signed TLS certs generated
locally) + iOS simulator where possible (simulator has no tunnel: probe core / config only). Output: a
machine-readable matrix (e.g. `doc/protocols.md` or a test-generated table) → README table. sing-box-lx (after R8):
same for its extras (XHTTP, AmneziaWG, MASQUE, TrustTunnel, SSL VPN, ...), separate column.

## R14. Audit against the official clients (medium; research first, then fixes as tasks)
Compare our native layers with SagerNet's apps: https://github.com/SagerNet/sing-box-for-android (SFA),
https://github.com/SagerNet/sing-box-for-apple (SFI/SFM), https://github.com/SagerNet/sing-box-for-desktop.
Checklist: libbox setup options, service lifecycle (start/stop/reload/boot/always-on), platform interface methods
(interface monitor, local DNS, connection owner, WIFI state, notifications), command client usage, memory/OOM
handling, network changes/sleep/wake, per-app proxy, error reporting, iOS NE specifics (on-demand, include all
networks, app group), desktop architecture (input for R10). Output: gap list with severity → fix tasks in this
roadmap. Ask before cloning (network): shallow clones into the scratchpad.

### R14 findings (2026-10-29, compared at the "Bump version 1.14.4" commits: SFA f87c2eb, SFI 2dd154e, desktop 8aab8ea)
Our Android layer is a near-literal SFA port (PlatformInterface, LocalResolver, network monitor, getInterfaces,
connection owner); ours adds setUnderlyingNetworks on change, routing wait, tile/boot/always-on. Gaps (severity):
- A1 med: crash/OOM reports (SFA `Libbox.promoteOOMDraft()`, CrashReportManager, OOMReportManager) - we collect none.
- A2 med (=R7): `allowBypass`; proxy-only ProxyService (FGS specialUse). A3 low (=R7): OOM killer/limit configurable.
- A4 low: `needWIFIState` without location permission - SFA stops with an alert, we only log (WIFI rules never match).
- A5 low: SFA AppChangeReceiver - per-app include lists ignore apps installed later until reconnect.
- I1 med: SFI provider init `LibboxPrepareCrashSignalHandlers` + NativeCrashReporter + `LibboxReinstallCrashSignalHandlers`,
  `LibboxPromoteOOMDraft()` after setup, `platformMetadata` - we have none on iOS.
- I2 med: SFI route overrides in openTun: excludeDefaultRoute (0.0.0.0/31, ::/127), autoRouteUseSubRangesByDefault
  (1.0.0.0/8 … 128.0.0.0/1 instead of default), excludeAPNsRoute (17.0.0.0/8 + push.apple.com proxy bypass),
  systemProxyEnabled toggle - we have none (only NE-level excludeAPNs 16.4+).
- I3 low-med: NE options enforceRoutes, excludeCellularServices (16.4+), excludeDeviceCommunication (17.4+); custom
  on-demand rules (SSID/interface) and restoring on-demand after stop ("wasOnDemandEnabled").
- I4 low: locale in the extension; tailscaleHostname = device name. Diff by design: our serviceStop also cancels the
  tunnel (SFI only closes the service).
- FIXED 2026-10-29 (2ff067e, c7fdaaa): A1/I1 core reports (`getCoreReports()`, promoteOOMDraft, platformMetadata;
  NO PLCrashReporter = no native iOS crash reports, no Prepare/ReinstallCrashSignalHandlers), A4 (warning in core log,
  no stop), I2 + I3 NE flags (settings `enforceRoutes`, `excludeCellularServices`, `excludeDeviceCommunication`,
  `excludeDefaultRoute`, `noDefaultRoute`, `excludeApnsRoute`). OPEN: A2/A3 + system proxy toggle (→ R7), A5,
  custom on-demand rules, iOS extension locale; none of the iOS options verified on a device (no tunnel in simulator).
- Desktop (input for R10): Electron+TS UI; the core runs as a privileged daemon (Windows service, named pipe
  `\\.\pipe\ProtectedPrefix\Administrators\sing-box`; Linux systemd `/run/sing-box.socket`); UI talks gRPC
  (DesktopService/StartedService/ManagedService). macOS = SFM in the apple repo (NE / system extension).

## R15. Dependency audit (small)
Today `dependencies`: flutter, plugin_platform_interface ^2.1.8, yaml ^3.1.2 (R3 Clash); dev: flutter_test,
flutter_lints ^6.0.0. Check: transitive deps (`flutter pub deps`), whether each is needed (yaml could stay or be
replaced only if trivial), minimum versions that still work with Flutter 3.29/Dart 3.7 (pana "supports latest
dependencies" + downgrade check `flutter pub downgrade` + tests), native deps (Android: androidx.core,
kotlinx-coroutines; iOS: none besides Libbox) and their licenses for THIRD_PARTY_NOTICES.md.

## Later
- R10 Desktop: macOS (shares the iOS NE code), Windows (sing-box.exe + service like flutter_sing_box, or libbox
  c-shared) — research.
- R11 Android service in a separate process (`:remote`, like SFA/flutter_sing_box) — evaluate trade-offs only.
- R12 Background subscription/rule-set updates (WorkManager, BGTaskScheduler); typed full config model (optional).
