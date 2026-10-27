# sing_box rewrite — HANDOFF (start here in a new chat)

Updated 2026-10-27 (end of session 3). Branch **`claude/package-study-navigators-83455e`** (all work committed).
Worktree `/Users/qusadprod/projects/sing_box/.claude/worktrees/singbox-flutter-plugin-review-22aa2f`.
If a new chat starts on a fresh branch cut from `main`, fast-forward it first (main has LFS files, git-lfs is absent):
`git -c filter.lfs.process= -c filter.lfs.clean= -c filter.lfs.smudge= -c filter.lfs.required=false merge --ff-only claude/package-study-navigators-83455e`

## 0. Rules from the user
- Goal: a fully working, fully featured `sing_box` Flutter VPN plugin (sing-box/libbox 1.14.4) with pub.dev-level
  docs, integrated into `example/`. Correctness over speed. Talk to the user in **Russian**.
- **No subagents.** Work sequentially. **Commit after every finished piece.** Save tokens: read only what you need.
- **Do not publish the libbox GitHub release** until the user says so (asked 2026-10-27).
- Avoid flutter_vless mistakes (§5; full study `doc/agent_notes/flutter_vless_research.md`, read only if needed).
- Local servers for tests must bind **127.0.0.1** (0.0.0.0 is blocked by the auto-mode classifier).

## 1. Where things are
| What | Where |
| --- | --- |
| Native ↔ Dart contract (source of truth) | `doc/platform_channel.md` |
| User docs | `README.md`, `doc/android.md`, `doc/ios.md`, `CHANGELOG.md`, `THIRD_PARTY_NOTICES.md` |
| Dart facade / config toolkit | `lib/src/sing_box.dart`, `lib/src/config/` |
| Android | `android/` (`SingBoxPlugin.kt`, `plugin/`, `core/`, `service/`) |
| iOS | `ios/sing_box/Package.swift` + `Sources/{sing_box,SingBoxShared,SingBoxTunnel}`, `ios/*.podspec`, `ios/libbox.rb`, `ios/scripts/add_packet_tunnel.rb` |
| libbox build/release | `scripts/build_libbox.sh`, `scripts/flatten_xcframework.sh`, `scripts/release_libbox.sh`, `.github/workflows/{ci,libbox}.yml` |
| Tests | `test/` (unit, fake platform `test/support/fake_platform.dart`), `test/config/` (+ `sing-box check`), `example/integration_test/` (`vpn_e2e`, `permission_e2e`, `smoke`, `server/` e2e servers) |

## 2. Environment
- Flutter 3.47.6 (`~/dev/flutter`), Xcode 27.1, Go 1.26 (`GOTOOLCHAIN=local`, `GOSUMDB=sum.golang.google.cn`).
- `export JAVA_HOME=/Library/Java/JavaVirtualMachines/jdk-21.jdk/Contents/Home` (default java 26 breaks Gradle).
- Android SDK `~/Library/Android/sdk`, adb `…/platform-tools/adb`, AVD `Medium_Phone` (Android 17):
  `~/Library/Android/sdk/emulator/emulator -avd Medium_Phone -no-window -no-audio -no-boot-anim -no-snapshot-save -gpu swiftshader_indirect` (run in background).
- iOS simulator `iPhone 17 Pro` = `8A43E948-95F2-419A-9440-C359804654F6`. Network Extensions do not run there.
- CocoaPods is Homebrew's (its `xcodeproj` gem is found by `add_packet_tunnel.rb`). `pana` is activated globally.
- Global Flutter config has SPM enabled. CocoaPods test: temporarily append
  `  config:\n    enable-swift-package-manager: false` under `flutter:` in `example/pubspec.yaml`, build, then
  `git checkout example/pubspec.yaml example/ios/Podfile.lock example/ios/Runner.xcodeproj/project.pbxproj`.
- Previous scratchpad (may be wiped): `/private/tmp/claude-501/-Users-qusadprod-projects-sing-box--claude-worktrees-singbox-flutter-plugin-review-22aa2f/74d8003d-46eb-43d7-aed2-deade4eeec8f/scratchpad`
  with `bin/sing-box` (1.14.4 CLI), `src/sing-box` (v1.14.4), `src/sfx-android` (@f87c2ebd), `src/sfx-apple` (@2dd154e7),
  `aar/classes.jar` (for `javap`). Re-create: clone at those refs; CLI = `go build -tags with_gvisor,with_quic,with_wireguard,with_utls,with_clash_api ./cmd/sing-box`.
- libbox binaries (gitignored): `build/libbox/{libbox.aar,Libbox.xcframework,Libbox.xcframework.zip}`, local copies
  `android/libs/libbox.aar`, `ios/sing_box/Frameworks/Libbox.xcframework`. Rebuild: `scripts/build_libbox.sh android apple --install`.

## 3. Key decisions (short)
- Binaries are not in git/pub: downloaded at build time from release `libbox-v1.14.4` (`QUSAD-prod/sing_box`) with
  SHA-256: aar `d5511581…6bae` (`android/libbox.properties`), xcframework zip `8bca7d8f…1c40` (`Package.swift`,
  after flattening — the old `0413d0…` is obsolete). Gradle/`libbox.rb` overrides: `SING_BOX_LIBBOX_AAR`,
  `SING_BOX_LIBBOX_XCFRAMEWORK_ZIP`, `SING_BOX_LIBBOX_BASE_URL`.
- Android: VpnService in the main process (FGS `systemExempted`), state in process (`ServiceState`), plugin sets
  `connecting` before the `start` result, Quick Settings tile (disabled component), boot receiver, KV = SharedPreferences.
- iOS: extension = `class PacketTunnelProvider: SingBoxPacketTunnelProvider {}`; the extension links the
  **`SingBoxTunnel` pod with static linkage** in both SPM and CocoaPods app modes (linking the SPM product conflicts
  with Flutter's folder-named package identity). Config file `<app group>/sing-box/config.json`, reload via provider message.
- Dart: `connect()` waits for `connected` → `SingBoxStartException` (core error) / `SingBoxTimeoutException` /
  `SingBoxCancelledException`; start/stop serialized; `pingServers()` (TCP without tunnel, URL test with it);
  speed/STUN tests run directly when the VPN is off.

## 4. State (all verified 2026-10-27)
- `flutter analyze` clean (plugin + example); `flutter test`: 246 pass + 3 skipped (with `SING_BOX_BIN`: all pass);
  `flutter pub publish --dry-run`: 244 KB, 0 warnings.
- Android: `flutter build apk --debug/--release` OK (universal release 235 MB). Emulator e2e `vpn_e2e_test.dart` 8/8,
  `permission_e2e_test.dart` 1/1.
- iOS: SPM simulator debug + `--release --no-codesign` (140 MB) OK; CocoaPods mode OK; `smoke_test.dart` 5/5 on the
  simulator; `add_packet_tunnel.rb` applied to `example/ios` (idempotent).

### Running the Android e2e
1. Start the emulator (§2). 2. `SING_BOX_BIN=<sing-box 1.14> example/integration_test/server/run_e2e_server.sh` (background).
3. `example/integration_test/server/grant_vpn_consent.sh` (background; `flutter test` may reinstall the app and reset consent).
4. `cd example && flutter test integration_test/vpn_e2e_test.dart -d emulator-5554 --dart-define=E2E_HOST=10.0.2.2`
   (run in background, it takes ~2 min incl. build). Permission test: stop the consent loop first.

## 5. Facts worth remembering
- libbox 1.14: no `setMemoryLimit` (→ `SetupOptions.oomKiller*`); `urlTestTime` is unix **seconds**; Android logs have
  ANSI colours; standalone command clients close after each call; `ServiceStop/Reload` run inside gRPC handlers.
- `urlTest(<single outbound>)` ignores the configured URL (uses gstatic) and deletes history on failure →
  `pingOutbound` tests through the outbound's `urltest` group. No standalone URL test exists in libbox.
- sing-box rejects unknown JSON fields. DNS server with host name + `detour` resolves via the detour; without detour it
  needs `domain_resolver`. Never `detour: direct` (fails lazily). Initial rule-set download failure aborts the start.
- Android: report the default interface **synchronously** in `startDefaultInterfaceMonitor` (else first-start
  "no available network interface"); Android 11+ package visibility hides apps from `VpnService.Builder` and
  `package_name` rules (needs `QUERY_ALL_PACKAGES`/`<queries>`); Android 17 `addAllowedApplication` accepts unknown
  packages silently; `setMetered(false)` + `setUnderlyingNetworks` = follow the real network.
- iOS: gomobile emits versioned frameworks → `flatten_xcframework.sh`; libbox Swift names
  `usePlatformAutoDetectControl()` / `autoDetectControl(_:)`; Libbox (static) is linked into both Runner and extension.
- flutter_vless lessons we follow: core in-process; truthful start result with exact error; serialized start/stop;
  validate config before replacing a session; immediate `startForeground`; null-intent start; no background
  `startService` for stop; Stop hidden under lockdown; iOS kill switch / On Demand / excludeLocalNetworks are options,
  never forced; provider shipped as a library class; XHTTP fails clearly.

## 6. Next tasks (in order)
1. **pana** (`dart pub global run pana --no-warning .` in the plugin root; target 160/160) and fix findings.
2. **CI sanity**: review `.github/workflows/ci.yml` / `libbox.yml` against the current scripts (flatten step is inside
   `build_libbox.sh`; scripts are now executable; example integration tests are not run in CI).
3. **Android manual scenarios on the emulator** (not automated yet): app closed (Back / swipe) while connected → VPN
   keeps running, reopening the app shows `connected`; QS tile (`adb shell cmd statusbar add-tile …` / `click-tile`);
   boot start (`startOnBoot` + `adb reboot`); Always-on/lockdown hides the Stop action. Idea: a tiny entrypoint
   `example/lib/e2e_harness.dart` built with `-t` that connects from `--dart-define`s and prints state to logcat.
4. **iOS review**: check `ios/sing_box/Sources/sing_box/TunnelController.swift` against the contract (status events,
   `last_error` on failed starts, `stop` disables On Demand, reload path) — device testing needs the user's paid team
   + iPhone (ask when ready).
5. Before publishing (on the user's request only): publish the libbox release (`scripts/release_libbox.sh --publish`,
   current `build/libbox` files), remove `doc/agent_notes/`, decide licensing (§7), bump version, squash if asked.

## 7. Open questions for the user
1. When to publish the GitHub release `libbox-v1.14.4` (pub users cannot download libbox before that).
2. License: libbox is GPL-3.0-or-later (+ naming clause), the plugin is MIT and named `sing_box` — relicense/rename?
3. macOS/desktop support and a proxy-only mode later?

## 8. Handy commands
```bash
export GOSUMDB=sum.golang.google.cn GOTOOLCHAIN=local JAVA_HOME=/Library/Java/JavaVirtualMachines/jdk-21.jdk/Contents/Home
flutter analyze && flutter test                      # plugin root
SING_BOX_BIN=<path>/sing-box flutter test test/config
cd example && flutter build apk --debug              # Android
cd example && flutter build ios --simulator --debug  # iOS (SPM)
cd example && flutter test integration_test/smoke_test.dart -d 8A43E948-95F2-419A-9440-C359804654F6
```
