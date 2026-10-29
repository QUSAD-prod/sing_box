---
name: navigator
description: "START HERE in a new sing_box chat: full state of release-1.1.0 (R0-R6 + SFA/SFI fixes done, pushed, CI green), rules, facts, open items, next tasks (R7), how to test, code map"
metadata:
  node_type: memory
  type: project
  originSessionId: 6e81f1f4-4e4f-462d-8363-f66a9f5d22e8
  modified: 2026-10-29T17:05:23.934Z
---

Rewritten in full on 2026-10-29 (evening) at the user's request as the handoff for the next chat.
Per-task plans: [[roadmap]]. Environment/toolchain: [[libbox-build-environment]].

## 0. Rules (read first)
- Talk **Russian**. The user is terse and impatient: report progress in short lines, never claim something is
  done/verified without proof (on 2026-10-29 I called Android R5 "done" while the navigator listed failing e2e tests -
  the user was furious). Re-read "Open / unverified" below before saying anything is finished.
- **No subagents** ([[feedback-no-subagents]]); work inline, commit after every finished piece.
- Commits: git identity of the user, **no Co-Authored-By trailer**, **never push** - give the user the push command
  ([[feedback-commits-and-push]]). All roadmap tasks go into branch `release-1.1.0`, never a new branch per task
  ([[feedback-one-release-branch]]).
- Network can be slow: ask before big downloads (SDKs, deps). Explicit user requests (e.g. "compare with SFA") count
  as consent for the clones they need.
- Every feature ships with: dartdoc on all public members (lint `public_member_api_docs`), tests (config ones call
  `expectSingBoxAccepts`), README section, CHANGELOG `## 1.1.0` entry, example app usage, doc/*.md notes when native.
- Dart code must compile with **Dart 3.7** (min Flutter 3.29): no null-aware map/list elements (`'k': ?v`), etc.
  `flutter analyze` enforces this through the SDK constraint.

## 1. Where things are
- Repo `github.com/QUSAD-prod/sing_box`. `main` = 1.0.0 (published on pub.dev manually, no tag / GitHub release).
- Work branch **`release-1.1.0`**, checked out in worktree
  `/Users/qusadprod/projects/sing_box/.claude/worktrees/singbox-flutter-plugin-review-22aa2f` (has the local libbox
  copies `android/libs/libbox.aar` + `ios/sing_box/Frameworks/Libbox.xcframework`, git-ignored). If a new chat
  starts in another worktree: that worktree may hold `release-1.1.0` checked out elsewhere - check `git worktree
  list`; free it with `git -C <other> switch <its claude/... branch>` (only if clean), then `git switch release-1.1.0`.
- **Pushed by the user 2026-10-29: `release-1.1.0` = `fb4e5b1`, nothing local/unpushed, tree clean.**
- **CI run 40914059314 (workflow_dispatch on fb4e5b1): all 8 jobs green** - Analyze & test (336 tests incl.
  `sing-box check`), libbox release, example Android, example iOS spm + cocoapods, Minimum Flutter 3.29.3 android /
  ios-spm / ios-cocoapods (the last two also run `dart run sing_box:setup_ios` and build with the extension).
  Run CI: `gh workflow run ci.yml --repo QUSAD-prod/sing_box --ref release-1.1.0`.
- Commits on top of main (oldest first): 576f207 WIP min Flutter 3.29 (R0) → 7bedc06 R1 → 1f58da7 R2 → 49681b2 R3 →
  2d918b9 docs → 3e020dc version 1.1.0 → 8b0101f CI min Flutter → 7e39ae9, 517aef5, e8a017b, 5ff09e0 (R4) → 3698bea
  (R5 Dart) → 0c769f7 "WIP R5 Android" → 72ae1bd "WIP R5 iOS" → dc21036 → 11521e0 → dcd2fdd → 2ff067e → c7fdaaa →
  a6c74da → fb4e5b1 (R6). Three commits still titled "WIP" are pushed: fix by **squash-merging** the release PR
  (no force push without the user's explicit OK).
- Version **1.1.0** everywhere (pubspec, podspecs, gradle, README, CHANGELOG). Release tag will be `v1.1.0`
  (publish workflow checks tag = `v` + pubspec version); release steps in `doc/releasing.md` (user pushes/tags).

## 2. Done in 1.1.0 (all on release-1.1.0, pushed)
- **R0** min Flutter 3.29 / Dart 3.7 ([[lower-min-flutter]]), CI job "Minimum Flutter".
- **R1** `SingBoxIpVersion` (dual/ipv4/ipv6). **R2** subscriptions by URL (`SingBoxSubscription`, provider headers).
  **R3** Clash/mihomo YAML (`yaml` dependency). **R4** routing: `SingBoxRoutingMode {proxyAll, proxyListed}`,
  `proxyDomains/proxySubnets/blockedInCountries`, custom ordered rules `SingBoxRoutingRule`, `blockQuic`,
  `bittorrentDirect`, rules JSON import/export, plugin-managed rule-set downloads (`getRuleSets/updateRuleSets/
  watchRuleSets`, local `.srs`, jsDelivr mirrors).
- **R5 four ping methods**: `SingBoxPingMethod {proxyHead (default), proxyGet, tcp, icmp, @Deprecated urlTest}`;
  `ping()`, `pingServers(method:)`, `pingOutbound(method:)`, `pingCurrentServer(method:)`; results have `method`,
  `url`, `statusCode`. Connected: probe routes `<probeAddress>:20000+i` → outbound i (route `override_address/port`
  to urlTestUrl host), app sends the HTTP request itself (`lib/src/latency_probe.dart`), fallback libbox urlTest.
  Stopped: temporary **probe core** in the app (2nd libbox CommandServer never `start()`ed; config `buildProbe()`:
  direct inbounds on 127.0.0.1; batches of 64). TCP/ICMP native outside the tunnel (contract method `pingServer`;
  Android `NativePing.kt` with protect; iOS `SingBoxNativePing.swift`, in the extension while connected via provider
  message `{"command":"ping",...}`). New option `SingBoxConfigOptions.probeAddress` (default `198.51.100.1`,
  '' disables). README "Latency (ping)" section, example method selectors (Home + Servers pages).
- **Android fix**: `connect()` reported connected before Android routed the app through the VPN → first request went
  around the tunnel (reset/hang; also in 1.0.0). `SingBoxVpnService.awaitRoutedThroughVpn()` waits ≤3 s
  (registerDefaultNetworkCallback until TRANSPORT_VPN) unless the app itself is excluded.
- **e2e** (example/integration_test/vpn_e2e_test.dart) deterministic: rule-set test uses `ir` fixtures
  (`server/rules/geoip-ir.json`, `geosite-category-ir.json`); "starts without the rules of unreachable rule-sets".
  **Android emulator e2e 8/8 in ~30 s** (last run after 2ff067e).
- **R14 comparison with official clients** (SFA/SFI at their "Bump version 1.14.4" commits, desktop 8aab8ea) and fixes:
  core crash/OOM reports `getCoreReports()/deleteCoreReport()/deleteCoreReports()`, `SingBoxCoreReport`
  (reads `<workingDir>/crash_reports|oom_reports`), `Libbox.promoteOOMDraft()` before the tunnel's command server,
  platformMetadata (OS/model; iOS NE options); Android warning in the core log for wifi_ssid/bssid rules without
  location permission; iOS options in `SingBoxSettings`/`SingBoxServiceOptions`: `enforceRoutes`,
  `excludeCellularServices`, `excludeDeviceCommunication`, `excludeDefaultRoute` (hide VPN icon), `noDefaultRoute`
  (sub-ranges), `excludeApnsRoute` (last three applied by the extension in openTun). Gap list: [[roadmap]] R14.
- **R6 iOS without CocoaPods**: `dart run sing_box:setup_ios` (`bin/setup_ios.dart`, `lib/src/tool/pbxproj.dart`
  = OpenStep plist parser + in-place text edits, `lib/src/tool/setup_ios.dart`). Links product `SingBoxTunnel`
  through Flutter's `FlutterGeneratedPluginSwiftPackage` reference when its Package.swift depends on `sing_box`,
  else adds `pod 'SingBoxTunnel'` to the Podfile; keeps an existing pod. `ios/scripts/add_packet_tunnel.rb` is now
  a wrapper calling the tool. Package.swift links UIKit. Tests `test/tool/setup_ios_test.dart` (fixture
  `test/tool/fixtures/flutter_3_47.pbxproj`, team id replaced by ABCDE12345 - never commit the user's real team
  <the user's team id>).

## 3. Technical facts learned (keep)
- sing-box 1.14 tun inbound: every TCP connection to the DNS hijack address (TUN address + 1, e.g. 172.19.0.2) is
  handled as DNS over TCP → never use it as a probe/ping address. sing-tun 0.9.7 has a ForwardDispatcher that judges
  flows by the first packet ("router: pre-match").
- Android `VpnService.establish()` returns before UID routing is applied (see fix above). Emulator slirp: requests to
  unreachable TEST-NET addresses hang ~minutes; emulator answers ICMP itself (ICMP numbers meaningless there).
- libbox writes crash logs to `<working>/CrashReport-<source>.log`, archived into `crash_reports/<time>/` by the next
  `Libbox.setup` of the same source; OOM drafts promoted to `oom_reports/` by `promoteOOMDraft`. Native iOS crash
  reports would need PLCrashReporter (not added). Every CommandServer (also the probe core) has its own OOM recorder.
- libbox iOS uses `UIDevice` → a SwiftPM-linked extension must link UIKit.
- Xcode resolves `XCSwiftPackageProductDependency` products through the package graph (product of a dependency of
  the referenced package works). Flutter puts plugins at `ios/Flutter/ephemeral/Packages/.packages/<plugin dir
  basename>` (pub cache: `sing_box-<version>` → changes on upgrade). With SPM disabled Flutter still generates
  FlutterGeneratedPluginSwiftPackage with empty deps. SPM apps have no `ios/.symlinks`.
- Dart: on iOS a reset during `Socket.connect` can surface as a bare `OSError` (catch it besides SocketException).
- CocoaPods CLI needs `LANG=en_US.UTF-8` here. New Swift files in the CocoaPods example need `pod install`.

## 4. Open / unverified (be honest about these)
- Nothing with a **running tunnel on a real iPhone** was ever tested (needs the user's paid team): extension ping
  path, iOS route/NE options, crash/OOM reports on iOS, local rule-sets read by the extension.
- Not verified on a device: rule-set files written to `<workingDir>/rule-sets` and reloaded by a running core.
- Probe core: calls libbox `saveConfigSnapshot` → overwrites the VPN's config snapshot used in crash reports; second
  OOM recorder in the same working dir; `freeLoopbackPorts` frees ports before the probe core binds them (race; iOS
  sim saw one connect reset in 6 runs → now a failed result).
- Manual Android lifecycle harness (doc/android.md "Checking the lifecycle on a device") not re-run after the
  DefaultNetworkMonitor owners refactor and the routing wait.
- `getCoreReports()` only unit-tested (no real crash/OOM triggered on a device).
- Still unchecked: `apply()` with `ipVersion` ≠ dual on a config without `dns`.

## 5. Next (priority queue)
1. **R7 engine options** ([[roadmap]] R7 + leftovers of R14): Android `allowBypass`; Android proxy-only mode
   (foreground service `specialUse`, no VpnService, mixed inbound); system HTTP proxy option in the Dart builder
   (tun `platform.http_proxy`; Android already calls setHttpProxy; Android `setSystemProxyEnabled` is a no-op
   today); configurable OOM killer / memory limit (SetupOptions oomKillerEnabled/oomMemoryLimit/oomKillerDisabled)
   for both platforms; iOS: document that proxy-only is impossible. Then R8 lx core (API design D1 = option A
   `SingBoxExtended extends SingBox`, details in [[roadmap]] R8) → R13 protocol matrix → R15 deps → R9 README/pub.dev
   (user's README order: protocol table first, platforms, features, install/docs, "Buy Me a Coffee" last - ask the
   link) → R10-R12.
2. **Release 1.1.0** whenever the user says: PR release-1.1.0 → main (squash merge), `doc/releasing.md`.
3. Remaining R14 gaps: AppChangeReceiver (per-app lists ignore newly installed apps), custom on-demand rules
   (SSID/interface), extension locale, PLCrashReporter (needs a new dependency - ask).

## 6. How to test
- `export PATH=$HOME/dev/flutter/bin:$PATH` (Flutter 3.47.6); `JAVA_HOME=/Library/Java/JavaVirtualMachines/jdk-21.jdk/Contents/Home`.
- Unit: `SING_BOX_BIN=<sing-box 1.14.4 CLI> flutter test` (336 tests); `flutter analyze`; `dart format
  --set-exit-if-changed lib test bin example/lib example/integration_test`; `flutter pub publish --dry-run` (warns
  only about uncommitted files; "Failed to update packages" = offline).
- sing-box CLI copy: `/private/tmp/claude-501/-Users-qusadprod-projects-sing-box--claude-worktrees-singbox-flutter-plugin-review-22aa2f/8247a254-ca94-472b-b200-064fc3ee0f06/scratchpad/bin/sing-box`
  (sources `.../scratchpad/src/sing-box`; /private/tmp may be wiped - rebuild per CONTRIBUTING.md).
- **Android e2e**: emulator `~/Library/Android/sdk/emulator/emulator -avd Medium_Phone -no-window -no-audio
  -no-boot-anim -no-snapshot-save -gpu swiftshader_indirect` (background); `SING_BOX_BIN=... example/integration_test/
  server/run_e2e_server.sh` (background; recompiles rules/*.json to www/*.srs); `sh example/integration_test/server/
  grant_vpn_consent.sh` (background); in example/: `flutter test integration_test/vpn_e2e_test.dart -d emulator-5554
  --dart-define=E2E_HOST=10.0.2.2 > log` (never pipe into `head` - it kills the run).
- **iOS simulator** `8A43E948-95F2-419A-9440-C359804654F6` (`xcrun simctl boot ...`): smoke
  `flutter test integration_test/smoke_test.dart -d <id>` (first run may hang - rerun); latency without tunnel:
  e2e server on the host + `flutter test integration_test/vpn_e2e_test.dart -d <id> --dart-define=E2E_HOST=127.0.0.1
  --plain-name "latency of profiles without the tunnel"` (setUpAll waits 30 s for VPN permission).
- Builds: in example/ `flutter build ios --simulator --debug`, `flutter build apk --debug`.
- setup_ios manual check: `flutter create --offline --org com.example --platforms ios -i swift app`, `flutter pub add
  --offline sing_box --path <repo>`, `flutter build ios --simulator --debug`, `dart run sing_box:setup_ios`, build
  again, check `build/ios/iphonesimulator/Runner.app/PlugIns/PacketTunnel.appex`. CocoaPods variant: add
  `config: enable-swift-package-manager: false` under `flutter:` in the app pubspec.
- Official clients for comparison (1.14.4 commits) were cloned to
  `/private/tmp/claude-501/-Users-qusadprod-projects-sing-box--claude-worktrees-singbox-flutter-plugin-review-22aa2f/6e81f1f4-4e4f-462d-8363-f66a9f5d22e8/scratchpad/ref/`
  (may be wiped; reclone shallow + `git fetch --shallow-since=2026-08-25 origin main`, commits SFA f87c2eb, SFI 2dd154e).

## 7. Code map
- `lib/sing_box.dart` exports (models one by one; `core_report.dart` with `hide loadCoreReports`).
  `lib/src/sing_box.dart` = `SingBox` facade (~2700 lines: init, connect queue, streams, pings (~line 1140-1700),
  settings, routing, rule-sets, core reports, server profiles, subscriptions).
- `lib/src/config/`: `config_builder.dart` (build/apply/buildProbe/probeTargets/_probeRules), `config_options.dart`
  (`probeAddress`), `routing_rules.dart`, `rule_sets.dart`, `share_link.dart`, `config.dart` (explicit exports - add
  new public config types there); `internal/` link parser, subscription, clash, writer.
- `lib/src/latency_probe.dart`, `lib/src/rule_set_manager.dart`, `lib/src/subscription_loader.dart`,
  `lib/src/models/*` (`ping_result.dart`, `core_report.dart`, `settings.dart`, ...), `lib/src/options.dart`
  (`SingBoxServiceOptions`, iOS/Android init options), `lib/src/tool/` (setup_ios, pbxproj; pure Dart).
- `bin/setup_ios.dart`. `doc/platform_channel.md` = native contract (change it first): methods incl. startProbe,
  stopProbe, pingServer, service option keys, "Crash and out-of-memory reports" section.
- Android `android/src/main/kotlin/com/qusadprod/sing_box/`: `SingBoxPlugin.kt`, `core/LibboxRuntime.kt` (setup),
  `service/SingBoxVpnService.kt`, `PlatformInterfaceImpl.kt`, `DefaultNetworkMonitor.kt` (owners vpn/probe),
  `ProbeCore.kt`, `NativePing.kt`, `LocalResolver.kt`, tile/boot/notification.
- iOS `ios/sing_box/Sources/`: `sing_box/` (plugin: SingBoxPlugin, TunnelController, ProbeCore, streams),
  `SingBoxShared/` (keys, paths, libbox setup + platformMetadata, SingBoxNativePing, SingBoxInterfaceMonitor),
  `SingBoxTunnel/` (SingBoxPacketTunnelProvider incl. ping message + OOM draft, SingBoxPlatformInterface with route
  overrides). `ios/sing_box/Package.swift` (local libbox override, conditional FlutterFramework, UIKit),
  podspecs + `ios/libbox.rb`.
- Tests: `test/config/*`, `test/sing_box_test.dart` + `test/support/fake_platform.dart` (probe core/routes fake),
  `test/latency_probe_test.dart`, `test/core_report_test.dart`, `test/models_test.dart`, `test/tool/*`.
  Example `example/lib/src/*_page.dart`; e2e `example/integration_test/`.
