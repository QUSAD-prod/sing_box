# sing_box rewrite — HANDOFF (start here in a new chat)

Last updated: 2026-10-27 (session 3), branch `claude/package-study-navigators-83455e` — it was
fast-forwarded from `claude/singbox-flutter-plugin-review-22aa2f` (old branch, no longer updated).
Worktree: `/Users/qusadprod/projects/sing_box/.claude/worktrees/singbox-flutter-plugin-review-22aa2f`
(main checkout `/Users/qusadprod/projects/sing_box`). This file supersedes `doc/REWRITE_NOTES.md`.
If a new session starts on a fresh branch from `main` again, fast-forward it first:
`git -c filter.lfs.process= -c filter.lfs.clean= -c filter.lfs.smudge= -c filter.lfs.required=false merge --ff-only <latest work branch>`
(`main` still has LFS-tracked framework files and git-lfs is not installed).

## 0. How to resume
1. `cd` into the worktree, `git log --oneline | head` (all work is committed as WIP commits).
2. Read this file, then `doc/platform_channel.md` (native contract) and the lessons in §6.
3. Continue with the task list in §5, in order. Commit after every finished piece.

### User's instructions (keep following them)
- Goal: fully review and rewrite the Flutter plugin `sing_box` (sing-box/libbox VPN), update everything, make it
  actually work, implement all functionality, verify everything, integrate it into `example/`, and write
  pub.dev-level documentation. Time is not a constraint; correctness is.
- **Do NOT use subagents** (they burned the usage limit twice). Do the work sequentially yourself.
- **Commit intermediate results often** (session limits cut work off). Talk to the user in Russian.
- The user previously used `flutter_vless`; avoid its mistakes (§6).
- The user approved building libbox from official sources and running local builds/tests (Gradle, Xcode,
  emulator, a local sing-box server for e2e).

## 1. Environment / toolchain
- Flutter 3.47.6 (`~/dev/flutter`), Dart 3.13.5, Xcode 27.1, Go 1.26 (`GOTOOLCHAIN=local`).
- **`sum.golang.org` is blocked** → `export GOSUMDB=sum.golang.google.cn`.
- Default java is JDK 26 → use `export JAVA_HOME=/Library/Java/JavaVirtualMachines/jdk-21.jdk/Contents/Home`.
- Android SDK `~/Library/Android/sdk` (NDK 28.2.13676358 + 30.0), adb at `~/Library/Android/sdk/platform-tools/adb`,
  AVDs `Medium_Phone`, `Small_Phone`. iOS simulators: iPhone 17 Pro Max etc. (NE does not run in the simulator).
- gomobile/gobind: `github.com/sagernet/gomobile@v0.1.13` installed in `~/go/bin`.
- `gh` is logged in as QUSAD-prod. git-lfs is not installed (the repo's LFS post-commit hook prints a harmless warning).
- Global Flutter config has `enable-swift-package-manager: true` — do not change global config; to test CocoaPods
  temporarily add `flutter: config: enable-swift-package-manager: false` to `example/pubspec.yaml`.
- Scratchpad (may be wiped): `/private/tmp/claude-501/-Users-qusadprod-projects-sing-box--claude-worktrees-singbox-flutter-plugin-review-22aa2f/74d8003d-46eb-43d7-aed2-deade4eeec8f/scratchpad`
  - `src/sing-box` = SagerNet/sing-box **v1.14.4** (`git clone --depth 1 --branch v1.14.4`); docs in `docs/configuration/`.
  - `src/sfx-android` = sing-box-for-android @ `f87c2ebdb7e34754be751bb5e58926db2fed8f8c` (reference Kotlin: `app/src/main/java/io/nekohasekai/sfa/bg/`).
  - `src/sfx-apple` = sing-box-for-apple @ `2dd154e7586188d5fff8de615e8c821ed25ec089` (reference Swift: `Library/Network/`).
  - `bin/sing-box` = sing-box CLI built from v1.14.4 (`go build -tags with_gvisor,with_quic,with_wireguard,with_utls,with_clash_api -o ../../bin/sing-box ./cmd/sing-box` inside `src/sing-box`).
  - `tpl_plugin/` = fresh `flutter create --template=plugin` reference (AGP 9.1 built-in Kotlin, SPM layout).
  To re-create: clone the repos at the commits above (`git init; git fetch --depth 1 origin <sha>; git checkout FETCH_HEAD`).

## 2. Key decisions
- **Core**: sing-box **1.14.4** libbox (`LIBBOX_VERSION`). Built by `scripts/build_libbox.sh [android] [apple] [--install]`
  (tags `with_gvisor,with_quic,with_wireguard,with_utls,with_clash_api,badlinkname,tfogo_checklinkname0`;
  Apple adds `with_dhcp,grpcnotrace` and `-tags-not-macos=with_low_memory`; Android `-androidapi 24`, `-libname=box`
  → `libbox.so`, so no `libgojni.so` clash with other gomobile plugins).
  - Outputs in `build/libbox/` (gitignored): `libbox.aar` (85 MB, 4 ABIs, sha256
    `d5511581e6275f10683f57bc8e7263badfa48c720d5d04acc741549fe6a66bae`), `Libbox.xcframework` (ios-arm64 +
    ios-arm64_x86_64-simulator) and `Libbox.xcframework.zip` (sha256/SwiftPM checksum
    `8bca7d8f5f8615df5d719a0e50fd2364d041cd2182ebda2d981d1e7494c71c40` — session 3: iOS slices flattened to shallow
    bundles by `scripts/flatten_xcframework.sh`, now run by `build_libbox.sh`; the old checksum `0413d0…` is obsolete).
  - Local dev copies (gitignored): `android/libs/libbox.aar`, `ios/sing_box/Frameworks/Libbox.xcframework`.
  - 16 KB page alignment verified: arm64-v8a/x86_64 `2**14` (Play requirement OK).
- **Distribution**: binaries are NOT in git and NOT in the pub package. Downloaded at build time from GitHub release
  `libbox-v1.14.4` of `QUSAD-prod/sing_box` (assets `libbox.aar`, `Libbox.xcframework.zip`) with SHA-256 check.
  `scripts/release_libbox.sh [--publish]` updates `LIBBOX_VERSION`, `android/libbox.properties`,
  `ios/sing_box/Package.swift` (`let libboxVersion = "..."`, `let libboxChecksum = "..."`) and publishes via `gh`.
  `.github/workflows/libbox.yml` builds + publishes on tag `libbox-v*`; `ci.yml` = analyze/test/publish dry-run + example builds.
- **Architecture**: Dart facade `SingBox` (lib/src/sing_box.dart) does config generation, persistence, ping/speed logic;
  native layers implement the thin contract `doc/platform_channel.md` (method channel `sing_box`, event channels
  `sing_box/{status,stats,logs,groups,outbounds,clash_mode,connections,notifications,network_quality,stun}`).
  Native talks to the core through libbox `CommandServer` (service side) and `CommandClient` (gRPC over
  `<basePath>/command.sock`; `statusInterval` in nanoseconds). Persistence = native KV (`storageRead/storageWrite`).
- **Android**: AGP 9.1, Kotlin DSL, built-in Kotlin (no `kotlin-android`), minSdk 24, compileSdk 36, VpnService in the
  main process (FGS type `systemExempted`, like SFA), status readable without an Activity, Quick Settings tile
  (disabled component, enabled via `setServiceOptions({quickSettingsTile})`), boot receiver, KV on SharedPreferences.
- **iOS**: SPM (`ios/sing_box/Package.swift`, products `sing-box` + `SingBoxTunnel`, targets `sing_box`,
  `SingBoxShared`, `SingBoxTunnel`, binary `Libbox` local-path-or-URL) + CocoaPods (`ios/sing_box.podspec`,
  `ios/SingBoxTunnel.podspec`, Ruby helper `ios/libbox.rb` downloads/verifies the zip). Host app adds a
  `PacketTunnel` NE target whose code is `class PacketTunnelProvider: SingBoxPacketTunnelProvider {}`.
  App group default `group.<bundle id>`, tunnel bundle id `<bundle id>.PacketTunnel` (configurable in initialize).
  Config handoff file `<app group>/sing-box/config.json`; reload via `sendProviderMessage({"command":"reload"})`.
- **pub.dev score** (was 120/160): fixed short description, URLs → `https://github.com/QUSAD-prod/sing_box`, LICENSE is
  pure MIT (third-party text moved to `THIRD_PARTY_NOTICES.md`), `example/` included (`.pubignore` rewritten),
  SPM support + built-in Kotlin in progress. Version 0.1.0, `sdk: ^3.12.0`, `flutter: '>=3.44.0'`.

## 3. Current state
| Area | State |
| --- | --- |
| libbox build + scripts | ✅ built, script works; release script + CI written, **not run** |
| Contract `doc/platform_channel.md` | ✅ (incl. Quick Settings tile + `requestAddQuickSettingsTile`) |
| Dart core (`lib/`) | ✅ `flutter analyze` clean, **245 tests pass** (+3 skipped without `SING_BOX_BIN`; 248 with it). Truthful `connect()` (waits for connected / `SingBoxStartException` / `SingBoxTimeoutException` / `SingBoxCancelledException`, serialized start/stop, generation token), `pingServers()` batch latency. Fake platform `test/support/fake_platform.dart` emulates connecting→connected/error and disconnecting→disconnected |
| Config module `lib/src/config/` | ✅ tested in `test/config/` (share links per scheme + malformed corpus + round trips, subscriptions, builder flags/options, `apply()` immutability, DNS/rule-sets/options); every generated config passes real `sing-box check` (`test/config/support/sing_box_check.dart`, `SING_BOX_BIN`) |
| Android native `android/` | ✅ (session 3) compiles, `flutter build apk --debug/--release` OK (release universal APK 235 MB: 3 ABIs × ~60 MB libbox stored uncompressed). `SingBoxPlugin.kt` + `plugin/{StreamHandlers,Converters}.kt` implement the whole contract. **e2e on emulator (Android 17, `example/integration_test/vpn_e2e_test.dart`) passes** against a local sing-box server — see §5.4. Notes: `doc/agent_notes/android.md` |
| iOS native `ios/` | ✅ (session 3) old `ios/Classes|Assets|Resources` deleted; SPM build (`flutter build ios --simulator --debug`, `--release --no-codesign` 140 MB) and CocoaPods build (`enable-swift-package-manager: false`) pass; `ios/sing_box.podspec`, `ios/SingBoxTunnel.podspec`, `ios/libbox.rb`; `ios/scripts/add_packet_tunnel.rb` (idempotent) added the `PacketTunnel` target to `example/ios`; extension links `SingBoxTunnel` **via CocoaPods with static linkage** in both modes (an SPM product reference conflicts with Flutter's folder-named package identity). `example/integration_test/smoke_test.dart` passes on the iPhone 17 Pro simulator. **Not tested on a device** (needs paid team + device: tunnel start, reload, on-demand, memory). Notes: `doc/agent_notes/ios.md` |
| Example | ✅ real `main.dart`; `integration_test/{vpn_e2e,permission_e2e,smoke}_test.dart`; Android QUERY_ALL_PACKAGES for per-app demo; iOS PacketTunnel target |
| Docs | ✅ README (iOS setup rewritten around the script), CHANGELOG, THIRD_PARTY_NOTICES, `doc/android.md`, `doc/ios.md`; `flutter pub publish --dry-run`: 244 KB, 0 warnings |

### Android e2e how-to (session 3)
- Servers bind to **127.0.0.1 only** (binding 0.0.0.0 is blocked by the auto-mode classifier); the emulator reaches
  host loopback as `10.0.2.2`. Server config: shadowsocks `aes-128-gcm`/`e2e-password` on 8388, vless (uuid
  `b831381d-…`, no TLS) on 10086, route rule `ip_cidr 203.0.113.80/32 → route-options override_address 127.0.0.1`;
  `python3 -m http.server 18080 --bind 127.0.0.1` serves `probe.txt` (`sing-box-e2e-ok`) and test `.srs` rule-sets
  (`sing-box rule-set compile`). The app fetches `http://203.0.113.80:18080/probe.txt`, which only works through the proxy.
- `flutter test integration_test/...` may **reinstall the app (new uid) and reset the VPN consent** → keep a host loop
  running `adb shell appops set com.qusadprod.sing_box_example ACTIVATE_VPN allow` every second during the run.
- Found + fixed by e2e: default interface reported asynchronously → first-start rule-set downloads failed with
  "no available network interface" (now synchronous like SFA); Android 17 `addAllowedApplication` silently accepts
  unknown packages and Android 11+ hides apps without `QUERY_ALL_PACKAGES` → start fails clearly when no
  `include_package` app is visible (example declares `QUERY_ALL_PACKAGES`, documented in doc/android.md).
- Result: `vpn_e2e_test.dart` **8/8 pass** (info/validation, TCP ping, connect + traffic via SS and VLESS verified in
  the server log, stats, groups, URL test, select, connections, clash modes, logs, switchServer/reload, stop, per-app
  include/exclude/not-installed, first-start rule-set download, core start error, rapid toggles, restart);
  `permission_e2e_test.dart` 1/1 (run without the consent loop; a fresh install has no consent).
- libbox `urlTest(<single outbound>)` ignores the configured URL and uses gstatic (and deletes the history on failure),
  so `pingOutbound` now tests via the outbound's `urltest` group when there is one.
- Not automated yet: engine detach/reattach (swipe away app, VPN keeps running), boot start, tile, Always-on, notification UI.

## 4. Facts about libbox 1.14.4 learned so far
- libbox has **no standalone URL test** of arbitrary outbounds (only through the running CommandServer) → profile
  latency without the tunnel is TCP-handshake based (`pingServers`).
- sing-box rejects unknown JSON fields (`json: unknown field "x"`), so `apply()` "unknown field preservation" means
  real sing-box fields the builder does not model (`ntp`, `udp_timeout`, `connect_timeout`, …).
- A DNS server with a host name + `detour` resolves the host through the detour outbound (verified in
  `common/dialer/dialer.go`: local resolution only when `!hasDetour || domain_resolver set`).
- `PlatformInterface` has ~26 methods (neighbor monitor, shell, bridge, tailscale hooks) — implement irrelevant ones as no-op.
- `Libbox.setMemoryLimit` is gone → `SetupOptions.oomKiller*` (SFA Android: off). `disableMemoryLimit` may be ignored on Android.
- Handler-bound `CommandClient.connect()` retries ~3.25 s then throws; standalone clients close after each call → new standalone client per op.
- `urlTestTime` from libbox is **unix seconds** (×1000 for the contract); connection timestamps are ms.
- Android logs contain ANSI colours (Dart strips them in `plainMessage`).
- `ServiceStop`/`ServiceReload` callbacks run inside gRPC handlers — must not block on closing the gRPC server.
- androidx.core 1.19 needs compileSdk 37 → use core-ktx 1.18.0; kotlinx-coroutines-android 1.11.0.
- STUN NAT mapping values: 0 unknown, 1 reserved, 2..4 (handled in `SingBoxNatMapping.fromValue`).
- Config (from the config agent): DNS server with a host name and no `detour` needs `domain_resolver`;
  never `detour: "direct"` for DNS/HTTP clients (fails lazily); remote rule-sets use top-level `http_clients`
  (`download_detour` deprecated in 1.14); initial rule-set download failure aborts start → only reference existing
  rule-sets; geosite country lists exist only for cn (`geosite-cn`), ru (`geosite-category-ru`), ir (`geosite-category-ir`);
  don't use geoip rule-sets in DNS rules; clash_api without `external_controller` doesn't listen but enables modes/stats.

## 5. Remaining tasks (in order)
1. ✅ (session 3) Config module tests + `sing-box check` validation. Fixed: VMess legacy cipher `aes-128-ctr`
   (was `aes-128-cfb`), `apply()` custom DNS never detours to an empty `direct`/`block` outbound (host names get a
   `local` bootstrap resolver instead of being dropped), invalid DNS addresses no longer consume tags.
2. ✅ (session 3) Truthful `connect()` (+ `connectToServer(s)`, `restart`) with `waitUntilConnected`/`timeout`;
   serialized start/stop + supersede/cancel; waits for a `disconnecting` session before starting;
   `watchConnectionState()` race fixed (async* dropped events between the initial yield and subscribing);
   `pingServers()` (TCP while stopped, URL test through the tunnel for running-config profiles; result has
   `serverId` + `method`); `SingBoxServerConfig` reads WireGuard peer / port-hopping addresses. Stop reason =
   existing `SingBoxConnectionState.error` (no extra field). **Native must honour the contract addition**:
   emit `connecting` before the `start` result, then `connected` or `disconnected`+`error` (doc/platform_channel.md §start).
3. ✅ (session 3) **Android native** (follow contract + SFA): finish `SingBoxPlugin.kt`, command-client streams with reconnect,
   network quality/STUN one-shot streams, VPN/notification permission flows (activity result; lifecycle-safe),
   `openVpnSettings`, KV storage, service options, tile. Must: `startForeground` immediately; handle null intent
   (sticky/always-on start → last config); stop in-process (no background `startService`); serialize start/stop;
   don't hardcode `setMetered(false)`; `SUPPORTS_ALWAYS_ON`; hide Stop action under lockdown; no extra permissions.
   Delete old broken sources. Then `flutter build apk --debug/--release` (JDK 21).
4. ✅ (session 3, see below) **Android e2e on emulator**: run `scratchpad/bin/sing-box run` with a shadowsocks (`aes-128-gcm`, 0.0.0.0:8388) and
   vless server config on the Mac; connect from the emulator to `10.0.2.2`; verify status, stats, logs, groups,
   urlTest/select, clash mode, connections, speed test, stop/reload, invalid config, permission denial, process kill
   (service survives, plugin reattaches). Grant consent via `adb shell appops set com.qusadprod.sing_box_example ACTIVATE_VPN allow`.
5. ✅ (session 3, simulator/compile level) **iOS native**: finish sources; podspecs + `libbox.rb`; PrivacyInfo; delete old `ios/Classes|Assets|Resources`;
   add `PacketTunnel` target to `example/ios` (bundle `com.qusadprod.singBoxExample.PacketTunnel`, app group
   `group.com.qusadprod.singBoxExample`, NE + App Groups entitlements, Info.plist `NSExtension…packet-tunnel`,
   `SingBoxAppGroup`), **Embed Foundation Extensions before Thin Binary**; link `SingBoxTunnel` in SPM and CocoaPods
   modes (check `example/ios/Flutter/ephemeral/Packages/` after `flutter build ios --config-only`); ideally a helper
   script `ios/scripts/add_packet_tunnel.rb` (xcodeproj gem). Prefer completion-handler `startTunnel`;
   `cancelTunnelWithError` when the core stops/fails; `sleep`/`wake` → pause/wake; NWPathMonitor; fail loudly when
   the app group container is nil. Builds: `flutter build ios --simulator --debug` and `--release --no-codesign`, SPM + CocoaPods.
   Simulator smoke test (initialize/version/checkConfig/storage/graceful VPN failure).
6. ✅ (session 3) **Example**: real `main.dart`, run on Android emulator and iOS simulator; `example/test` widget smoke test optional.
7. ✅ (session 3; re-check after device tests) **Docs**: `doc/android.md`, `doc/ios.md` (setup, troubleshooting, Always-on, ProGuard, offline builds, signing),
   update README with final integration steps from native work; CHANGELOG.
8. **Verification**: `dart format --set-exit-if-changed`, `flutter analyze`, `flutter test`, `pana` (target 160/160),
   `flutter pub publish --dry-run` (package size), CI workflows sanity.
9. Remove `doc/REWRITE_NOTES.md` and `doc/agent_notes/` before publishing (already in `.pubignore`), squash/clean commits on user request.

## 6. flutter_vless lessons (full study: `doc/agent_notes/flutter_vless_research.md`, coverage verified: all 28 tracker items, upstream flutter_v2ray, forks, 1.1.7 changelog)
Must-haves for our plugin:
- Core in-process via libbox (no exec'd binaries → no `useLegacyPackaging`/AAB/SELinux "connected but no internet" class of bugs).
- Truthful state: start resolves after start or throws with the **exact core error**; status stream + `getStatus()` with
  initial emit; error/stop reason field; reset speed baselines per session; no stuck CONNECTED after rapid toggles
  (serialize start/stop, ignore events of earlier sessions, cancel superseded starts).
- Validate a new config before replacing a working session (we `checkConfig` before reload — keep it).
- Preserve unknown JSON fields when patching user configs (`apply()` deep-copies — keep testing it).
- Android: immediate `startForeground`; null-intent handling; no background `startService` for stop; permission flow
  safe against lifecycle; RECEIVER_NOT_EXPORTED; per-app lists really applied to `VpnService.Builder` (test it);
  notification fully customizable incl. speed + stop; Quick Settings tile with PendingIntent `startActivityAndCollapse`
  on API 34+ and state readable when the engine is dead; 16 KB alignment; no unneeded permissions.
- iOS: provider shipped as a library class (never a copied file); configurable ids; "Cycle inside Runner" fix in docs;
  memory 50 MB (with_low_memory, OOM killer options); cancel tunnel when core dies; wake/path-change recovery;
  kill switch / On Demand / excludeLocalNetworks / excludeAPNs as **options** (flutter_vless forced them and broke LAN);
  no hard-coded DNS; IPv6 supported; config not in plaintext providerConfiguration.
- Ping: libbox URL test through the proxy; typed result; batch ping for profiles; configurable URL.
- Links: vless (reality/vision/ws/grpc/h2/httpupgrade), vmess, trojan, ss (SIP002 + legacy + plugins), hy2, tuic, socks,
  http, wireguard; **XHTTP is unsupported in sing-box → fail clearly**.
- Process: CI builds the example on every platform; changelog flags integrator actions.
- Requested features we cover/plan: per-app include/exclude, routing/geo rule-sets, LAN bypass, DoH/DoT, FakeIP, IPv6,
  kill switch/always-on/on-demand, status/stats/logs streams, ping (single + batch), core version, notification
  customization, QS tile. Not planned yet: desktop/Linux, proxy-only mode, iOS Control Center widget.

### Next session — what is left
- **iOS on a real device** (user: paid team + iPhone): run the example, `connect` to a server, reload/switchServer,
  stop, start errors from the extension (`last_error` path), On Demand, kill switch, memory under load. The Dart
  contract requires the `connecting` event before the `start` result — verify the iOS TunnelController emits it
  (NEVPNStatus `.connecting` arrives asynchronously; Dart tolerates it, but check the timeout path).
- Android manual checks not automated: swipe the app away while connected (VPN keeps running, new engine attaches),
  notification Stop + lockdown, boot start, QS tile, Always-on.
- §5.8 verification: `pana` (target 160/160), CI workflows sanity (`.github/workflows/ci.yml`, `libbox.yml`) — they
  should run `flatten_xcframework.sh` via `build_libbox.sh` (already wired).
- **Publish the libbox GitHub release** (§7.1) with the *new* `build/libbox/Libbox.xcframework.zip` (checksum above).

## 7. Open questions for the user
1. **GitHub release** `libbox-v1.14.4` must be published (`scripts/release_libbox.sh --publish` or push tag
   `libbox-v1.14.4` to run `.github/workflows/libbox.yml`) — without it pub users can't download libbox.
2. **License**: libbox is GPL-3.0-or-later (+ clause forbidding use of the sing-box name to imply association), the
   plugin is MIT and named `sing_box`. Consider relicensing to GPL-3.0 and/or renaming; currently README/THIRD_PARTY_NOTICES warn.
3. Whether to add macOS/desktop support and a proxy-only mode later.

## 8. Handy commands
```bash
export GOSUMDB=sum.golang.google.cn GOTOOLCHAIN=local JAVA_HOME=/Library/Java/JavaVirtualMachines/jdk-21.jdk/Contents/Home
flutter analyze && flutter test
cd example && flutter build apk --debug          # Android
cd example && flutter build ios --simulator --debug   # iOS (SPM)
scripts/build_libbox.sh android apple --install   # rebuild libbox
SING_BOX_BIN=$SCRATCH/bin/sing-box flutter test test/config
```
