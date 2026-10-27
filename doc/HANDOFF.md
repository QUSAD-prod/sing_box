# sing_box rewrite — HANDOFF (start here in a new chat)

Updated 2026-10-28 (end of session 4). Branch **`claude/package-research-navigators-9311b3`** contains all
previous work branches (`claude/package-study-navigators-83455e`, `claude/singbox-flutter-plugin-review-22aa2f`).
Worktree `/Users/qusadprod/projects/sing_box/.claude/worktrees/singbox-flutter-plugin-review-22aa2f`.
If a new chat starts on a fresh branch cut from `main`, fast-forward it first (main has LFS files, git-lfs is absent):
`git -c filter.lfs.process= -c filter.lfs.clean= -c filter.lfs.smudge= -c filter.lfs.required=false merge --ff-only claude/package-research-navigators-9311b3`
Commits are authored by the user's git identity without Claude co-author trailers; **only the user pushes** —
never push.

## 0. Rules from the user
- Goal: a fully working, fully featured `sing_box` Flutter VPN plugin (sing-box/libbox 1.14.4) with pub.dev-level
  docs, integrated into `example/`. Correctness over speed. Talk to the user in **Russian**.
- **No subagents.** Work sequentially. **Commit after every finished piece.** Save tokens: read only what you need.
- **Do not publish the libbox GitHub release** until the user says so (asked 2026-10-27).
- Avoid flutter_vless mistakes (§5; full study `doc/agent_notes/flutter_vless_research.md`, read only if needed).
- Local servers for tests must bind **127.0.0.1** (0.0.0.0 is blocked by the auto-mode classifier).
- Commits: no `Co-Authored-By: Claude` trailer, author = user's git config; **never push** (the user pushes).

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

## 4. State (verified 2026-10-28, session 4)
- `dart format` clean, `flutter analyze` clean (plugin + example); `flutter test` with `SING_BOX_BIN`: 251 pass, none
  skipped (session 4); `flutter pub publish --dry-run`: 0 warnings; pana 150/160 (§6).
- Android: `flutter build apk --debug/--release` OK (universal release 235 MB). Manual lifecycle scenarios pass on the
  Android 17 emulator (Back/swipe, QS tile, boot start, update restart, Always-on + lockdown). Emulator e2e
  `vpn_e2e_test.dart` 8/8 and `permission_e2e_test.dart` 1/1 (session 4).
- iOS: SPM simulator debug + `--release --no-codesign` (140 MB) OK; `smoke_test.dart` 5/5 on the simulator (session 4);
  CocoaPods mode OK in session 3; `add_packet_tunnel.rb` applied to `example/ios` (idempotent).
- Local dev copy `android/libs/libbox.aar` (gitignored) = `build/libbox/libbox.aar`; needed until the release exists.

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
- Android lifecycle (verified session 4, `example/lib/e2e_harness.dart`, see `doc/android.md`): `isLockdownEnabled()`
  is false until `establish()` → the notification is rebuilt after connect; non-active QS tiles ignore
  `requestListeningState` and refresh only while the panel is open (`cmd statusbar expand-settings` before
  `click-tile`); `settings put secure always_on_vpn_*` needs a few seconds before `adb reboot` to persist.
- sing-box 1.14 resolves outbound server names with the only DNS server when `route.default_domain_resolver` is
  missing and **rejects** configs with several servers → `apply()` pins the previous resolver when adding DNS.
- sing-box CLI for tests: clone v1.14.4 into the scratchpad, `go build -trimpath -tags
  with_gvisor,with_quic,with_wireguard,with_utls,with_clash_api -ldflags "-X github.com/sagernet/sing-box/constant.Version=1.14.4" ./cmd/sing-box`
  (the user allowed it on 2026-10-28; the auto-mode classifier refuses it without that).
- libbox release assets must be the files whose SHA-256 is committed; CI rebuilds never match (`release_libbox.sh`
  refuses to replace differing assets without `--force`).
- flutter_vless lessons we follow: core in-process; truthful start result with exact error; serialized start/stop;
  validate config before replacing a session; immediate `startForeground`; null-intent start; no background
  `startService` for stop; Stop hidden under lockdown; iOS kill switch / On Demand / excludeLocalNetworks are options,
  never forced; provider shipped as a library class; XHTTP fails clearly.

## 6. Next tasks (in order)
1. **iOS on a device**: the session-4 `TunnelController` changes (synthetic `connecting` until iOS reports the start,
   errors of fast-failing starts, no stale `fetchLastDisconnectError` after `stop()`, `reload` error codes) compile and
   pass the simulator smoke test, but Network Extensions only run on a device — needs the user's paid team + iPhone.
2. **CI**: the native jobs fail until the libbox release exists; the `dart` job now builds the sing-box CLI.
3. Before publishing (on the user's request only): publish the libbox release (`scripts/release_libbox.sh --publish`,
   current `build/libbox` files — never a CI rebuild, see `libbox.yml`), remove `doc/agent_notes/`, decide licensing
   (§7), bump version, squash if asked. pana is 150/160 only because `origin/main` still has the old `repository`
   URL in pubspec — 160/160 once this branch is on main.

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
