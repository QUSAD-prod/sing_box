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
