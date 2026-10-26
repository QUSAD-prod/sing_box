# sing_box rewrite — working notes (temporary, remove before publishing)

Status file for the ongoing full rewrite so work can resume in a new session.
Branch: `claude/singbox-flutter-plugin-review-22aa2f`.

## Decisions
- Core: sing-box **v1.14.4** libbox (`LIBBOX_VERSION`), built by `scripts/build_libbox.sh`
  (needs `GOSUMDB=sum.golang.google.cn` on this network; JDK 21 for Android).
  Local outputs: `build/libbox/` (+ `.sha256`), installed (gitignored) into
  `android/libs/libbox.aar` and `ios/sing_box/Frameworks/Libbox.xcframework`.
- Binaries are NOT committed / NOT in the pub package. They are downloaded at build time from
  GitHub release `libbox-v1.14.4` of `QUSAD-prod/sing_box` (assets `libbox.aar`,
  `Libbox.xcframework.zip`). The release still has to be created by the user.
  - libbox.aar sha256 `d5511581e6275f10683f57bc8e7263badfa48c720d5d04acc741549fe6a66bae`
  - Libbox.xcframework.zip sha256 `0413d065d147c1cb7c55c59315b60e5507a5e0bfb2e3c95696c5fa7c25a2da68`
- Native contract: `doc/platform_channel.md` (method channel `sing_box`, event channels
  `sing_box/{status,stats,logs,groups,outbounds,clash_mode,connections,notifications,network_quality,stun}`).
- Dart: facade `SingBox` (lib/src/sing_box.dart), models in lib/src/models, exceptions, options,
  persistence over native KV (`storageRead/storageWrite`), config builder + share links in lib/src/config.
- iOS: SPM (`ios/sing_box/Package.swift`) + CocoaPods; separate tunnel library for the
  Packet Tunnel extension; example has a `PacketTunnel` target.
- Android: AGP 9 / built-in Kotlin, VpnService (systemExempted FGS), libbox CommandServer.
- pub.dev score fixes: short description, URLs -> github.com/QUSAD-prod/sing_box, LICENSE must
  contain only the license text (third-party notices moved), include example/, SPM support,
  built-in Kotlin.
- License concern to raise with the user: libbox is GPL-3.0 (+ naming clause) while the plugin is MIT.

## Work split (parallel agents)
- Android native (android/, example/android/) — e2e test on emulator against a local sing-box server.
- iOS native (ios/, example/ios/).
- Dart config module (lib/src/config/, test/config/).
- Research of flutter_vless + its issues (report only).
- Lead: rest of lib/, tests, example/lib, docs, CI, release script.

## Progress log
- [x] libbox 1.14.4 built for Android (4 ABIs) and iOS (device + simulator)
- [x] contract written, example platform folders regenerated from Flutter 3.47 template
- [ ] Dart core (models/exceptions/options done; platform interface, method channel, facade, storage pending)
- [ ] Android native, iOS native, config module, research — in progress
- [ ] example app UI, README/CHANGELOG/docs, CI workflow + release script, final verification

## Checkpoint 2 (lead)
- Done in lib/: exceptions.dart, options.dart, storage.dart, utils/validators.dart, all models
  (connection_status/stats, log_entry, outbound_group, connection, clash_mode, network_quality,
  stun_result, ping_result, speed_test_result, sing_box_notification, settings, server_config,
  runtime_info), observer (SingBoxObserver with no-op defaults, Talker fixed),
  sing_box_platform_interface.dart, sing_box_method_channel.dart.
- NEXT: lib/src/sing_box.dart facade (connect/buildConfig via lib/src/config/config.dart barrel,
  rules/settings/servers persistence via SingBoxStorage, ping via urlTest + outbounds stream,
  testSpeed via network quality), lib/sing_box.dart exports, tests with fake platform,
  real example app (example/lib/main.dart is a temporary placeholder on purpose).
- Agents running at checkpoint: Android native, iOS native, Dart config module, flutter_vless research.
  If they were interrupted, check android/, ios/, lib/src/config/ for partial work and resume.

## Checkpoint 3 — session stopped by usage limit (2026-10-27)
All four sub-agents were stopped before writing files (they had only read references). Relaunch them
in the next session with these briefs (full context: doc/platform_channel.md + this file):
1. Android: rewrite android/ (build.gradle.kts, AGP 9.1, built-in Kotlin, minSdk 24, compileSdk 36),
   libbox resolution: gradle prop `singBox.libboxAar` / env `SING_BOX_LIBBOX_AAR` -> android/libs/libbox.aar ->
   download release asset to <gradleUserHome>/caches/sing_box/libbox/<ver>/ with sha256 (android/libbox.properties).
   VpnService (systemExempted FGS), CommandServer.startOrReloadService, PlatformInterface per SFA
   (reference clone: scratchpad/src/sfx-android at submodule commit f87c2ebd), all channels of the contract,
   boot receiver, KV storage. Verify flutter build apk debug/release + e2e on emulator vs local sing-box server.
2. iOS: ios/sing_box/Package.swift (products `sing-box` + `SingBoxTunnel`, binaryTarget local path or release url+checksum),
   sing_box.podspec + separate SingBoxTunnel.podspec (download zip in podspec Ruby if missing),
   SingBoxPacketTunnelProvider open class (ref: sfx-apple at 2dd154e7), example/ios PacketTunnel target
   (bundle com.qusadprod.singBoxExample.PacketTunnel, app group group.com.qusadprod.singBoxExample), SPM + CocoaPods builds.
3. Dart config module lib/src/config/ (+ barrel config.dart): SingBoxRoutingRules, SingBoxConfigOptions/Tun/Dns,
   SingBoxConfigBuilder(build/buildFromJson/apply; tags proxy/auto/direct), SingBoxShareLink (vless/vmess/trojan/ss/hy2/tuic/socks/http…),
   SingBoxDnsServer; tests validated with `sing-box check` (build CLI from scratchpad/src/sing-box).
4. Research flutter_vless (pub.dev + github.com/XIIIFOX/flutter_vless issues) -> doc/agent_notes/flutter_vless_research.md.
Note: scratchpad (/private/tmp/...) may be wiped; re-clone sing-box v1.14.4 and the SFA/SFI repos at the commits above
and rebuild libbox with scripts/build_libbox.sh if build/libbox is gone.
