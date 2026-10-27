# iOS agent notes (ios/**, example/ios/**)

Status: IN PROGRESS (2026-10-27) — design done, writing sources.

## Design (decided)
- `ios/sing_box/Package.swift` (single source of truth for libbox version/URL/checksum; the Ruby
  helper `ios/libbox.rb` parses the `let libbox* = "..."` lines from it).
  Targets: `Libbox` (binary: local `Frameworks/Libbox.xcframework` if it exists, else release URL+checksum),
  `SingBoxShared` (app group/paths/keys/libbox setup/iterators; Libbox only),
  `SingBoxTunnel` (open `SingBoxPacketTunnelProvider` + `ExtensionPlatformInterface`; no Flutter),
  `sing_box` (Flutter plugin: FlutterFramework + SingBoxShared + Libbox; PrivacyInfo resource).
  Products: `sing-box` -> [sing_box], `SingBoxTunnel` -> [SingBoxTunnel].
- Sources use `#if SWIFT_PACKAGE import SingBoxShared #endif`; CocoaPods compiles the Shared sources
  into each pod's own module instead.
- CocoaPods: `ios/sing_box.podspec` (plugin, Flutter dep, sources sing_box + SingBoxShared) and
  `ios/SingBoxTunnel.podspec` (sources SingBoxTunnel + SingBoxShared). Both vendor
  `sing_box/Frameworks/Libbox.xcframework`, ensured by `ios/libbox.rb` (download to
  `~/Library/Caches/sing_box/libbox/<ver>/`, sha256 verify, unzip into pod dir; env `SING_BOX_LIBBOX_BASE_URL`).
- Extension reads config from `<container>/sing-box/config.json` (written by app before start/reload).
  Reload: app -> `sendProviderMessage({"command":"reload"})` -> extension re-reads file -> startOrReloadService.
  Last start/stop error: extension writes `<container>/sing-box/last_error`, app reads it on disconnect
  (+ `fetchLastDisconnectError` iOS 16+).
- Notifications: extension posts local notification + appends to app-group defaults
  `sing_box.pending_notifications` + Darwin notify `<appGroup>.sing_box.notification`.

## Next steps
1. Write sources + Package.swift + podspecs.
2. `flutter build ios --config-only` in example, inspect ephemeral/Packages.
3. ios/scripts/add_packet_tunnel.rb, apply to example.
4. Builds SPM + CocoaPods, simulator harness.
