# Contributing to sing_box

Thanks for helping! This document covers the development setup, the test
suites and the design rules of the plugin. Releases are described in
[doc/releasing.md](doc/releasing.md).

By contributing you agree that your contribution is licensed under the
GPL-3.0-or-later, like the rest of the project.

## Repository layout

| Path | Contents |
| --- | --- |
| `lib/` | Dart API: `SingBox` facade, config toolkit (`lib/src/config/`), models, platform interface and method channel |
| `android/` | Kotlin implementation: plugin (`SingBoxPlugin.kt`, `plugin/`), core helpers (`core/`), `VpnService`, tile, boot receiver (`service/`) |
| `ios/` | Swift implementation: `sing_box/Package.swift` with `Sources/{sing_box,SingBoxShared,SingBoxTunnel}`, CocoaPods specs, `libbox.rb`, `scripts/add_packet_tunnel.rb` |
| `doc/` | Platform guides and the native <-> Dart contract (`platform_channel.md`) |
| `scripts/` | Building, releasing and verifying the libbox binaries |
| `test/` | Unit tests; `test/config/` validates generated configs with the real sing-box CLI |
| `example/` | Example app, integration tests (`integration_test/`) and local e2e servers (`integration_test/server/`) |

`doc/platform_channel.md` is the source of truth for the native side: change it
together with both platform implementations and the Dart method channel.

## Requirements

- Flutter (stable) matching `environment` in `pubspec.yaml`.
- Android: Android SDK + NDK, JDK 17 or 21 for Gradle (newer JDKs may not be
  supported by the Android Gradle Plugin yet).
- iOS: Xcode, CocoaPods (for the CocoaPods mode). VPN tunnels need a device and
  a paid Apple Developer team; the Simulator runs everything except the tunnel.
- Go 1.25+ for building libbox or the sing-box CLI.

## The native core (libbox)

The plugin downloads `libbox.aar` / `Libbox.xcframework.zip` from the GitHub
release `libbox-v<LIBBOX_VERSION>` and verifies them with the SHA-256 pinned in
`android/libbox.properties` and `ios/sing_box/Package.swift`. For development
without that download, build and install local copies (git-ignored):

```bash
scripts/build_libbox.sh android apple --install
```

This puts `android/libs/libbox.aar` and `ios/sing_box/Frameworks/Libbox.xcframework`
into the plugin; both build systems prefer them over the download. Copying an
existing `build/libbox/libbox.aar` to `android/libs/` works as well.

## Checks before a pull request

```bash
dart format --output=none --set-exit-if-changed lib test example/lib example/integration_test
flutter analyze
(cd example && flutter analyze)
flutter test
flutter pub publish --dry-run
```

CI runs the same checks plus Android and iOS (SwiftPM and CocoaPods) builds of
the example, and builds a fresh app made by the oldest supported Flutter
(`MIN_FLUTTER` in `.github/workflows/ci.yml`, keep it in sync with
`environment.flutter` in `pubspec.yaml`) for Android and iOS (CocoaPods and
SwiftPM). The builds run only after the *libbox release* job confirmed that
the libbox files of `LIBBOX_VERSION` are published with the pinned checksums
(`scripts/verify_libbox_release.sh`).

### Config tests with the real sing-box

Every config the toolkit generates is validated with `sing-box check` when
`SING_BOX_BIN` points to a sing-box CLI of the `LIBBOX_VERSION`:

```bash
git clone --depth 1 --branch v1.14.4 https://github.com/SagerNet/sing-box.git /tmp/sing-box
(cd /tmp/sing-box && go build -trimpath \
  -tags with_gvisor,with_quic,with_wireguard,with_utls,with_clash_api \
  -ldflags "-X github.com/sagernet/sing-box/constant.Version=1.14.4" \
  -o /tmp/sing-box-cli ./cmd/sing-box)
SING_BOX_BIN=/tmp/sing-box-cli flutter test
```

Without `SING_BOX_BIN` the structural assertions still run and three tests are
skipped. sing-box rejects unknown fields, so always run these tests after
changing the config toolkit.

### Android end-to-end tests (emulator)

```bash
# 1. An emulator (API 24+), e.g. `emulator -avd <name> -no-window -no-audio`
# 2. Local servers (listen on 127.0.0.1; the emulator reaches them as 10.0.2.2)
SING_BOX_BIN=/tmp/sing-box-cli example/integration_test/server/run_e2e_server.sh &
# 3. Keep granting the VPN consent (`flutter test` reinstalls the app)
example/integration_test/server/grant_vpn_consent.sh &
# 4. Tests
cd example
flutter test integration_test/vpn_e2e_test.dart -d emulator-5554 --dart-define=E2E_HOST=10.0.2.2
```

`vpn_e2e_test.dart` connects through Shadowsocks and VLESS servers, switches
servers in place, checks per-app lists, rule-set downloads, exact start errors
and rapid toggles. For `permission_e2e_test.dart` stop the consent loop first
(a fresh install has no consent).

Lifecycle scenarios that cannot be automated well (closing the app, Quick
Settings tile, boot start, app updates, Always-on VPN with lockdown) are checked
with `example/lib/e2e_harness.dart`; see
[doc/android.md](doc/android.md#checking-the-lifecycle-on-a-device).

### iOS

```bash
cd example
flutter build ios --simulator --debug                      # SwiftPM mode
flutter test integration_test/smoke_test.dart -d <simulator id>
flutter build ios --release --no-codesign
```

To check the CocoaPods mode, add `config: enable-swift-package-manager: false`
under `flutter:` in `example/pubspec.yaml` temporarily (or run
`flutter config --no-enable-swift-package-manager`) and build again. Tunnel
behaviour (start errors, reloads, On Demand) can only be tested on a device.

## Design rules

These come from real failures of earlier VPN plugins and of sing-box itself;
please keep them.

**Lifecycle**

- The core runs in the app process (Android) / the extension (iOS); the Dart
  side never owns tunnel state, it mirrors the platform's state.
- `connect()` reports the real outcome: `connected`, or the exact core error.
  The platform emits `connecting` before the `start` result, and start/stop
  requests are serialized.
- Configs are validated before they replace a running session.
- Android: `startForeground` immediately in `onStartCommand`, also for system
  (null-intent, Always-on) starts; stopping never uses a background
  `startService`; the Stop action is hidden under Always-on lockdown
  (`isLockdownEnabled()` is only true once the tunnel is established).
- iOS: kill switch, On Demand and `excludeLocalNetworks` are options and never
  forced; the provider ships as a library class
  (`class PacketTunnelProvider: SingBoxPacketTunnelProvider {}`); the extension
  links the `SingBoxTunnel` pod statically in both SwiftPM and CocoaPods app
  modes.

**sing-box / libbox 1.14 facts**

- Unknown JSON fields are rejected. A DNS server with a host name needs a
  `detour` or a `domain_resolver`; never use `detour: direct`. With more than one
  DNS server, `route.default_domain_resolver` is mandatory.
- A failed initial rule-set download aborts the start.
- `urlTest(<single outbound>)` ignores the configured URL; latency is measured
  through the outbound's `urltest` group. `urlTestTime` is in Unix seconds.
- Standalone command clients close after each call; `ServiceStop`/`ServiceReload`
  run inside gRPC handlers and must not block on shutdown.
- Android: report the default interface synchronously in
  `startDefaultInterfaceMonitor`; Android 11+ package visibility also hides
  apps from `VpnService.Builder` and `package_name` rules.
- iOS: gomobile emits versioned frameworks, `scripts/flatten_xcframework.sh`
  makes them iOS-shaped (run by `build_libbox.sh`).

**Release binaries**

- Release assets must be exactly the files whose SHA-256 is committed. CI
  rebuilds are not byte-identical, so they are never published;
  `scripts/release_libbox.sh` refuses to replace a different asset without
  `--force`.

## Commit messages

Use the imperative mood and explain *why* in the body when it is not obvious
(`Android: hide Stop under Always-on lockdown`).
