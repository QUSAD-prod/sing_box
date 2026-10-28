# Third-party notices

`sing_box` is licensed under the GNU General Public License v3.0 or later
([LICENSE](LICENSE)). It builds on the following projects.

## sing-box (libbox)

- Source: https://github.com/SagerNet/sing-box (version pinned in `LIBBOX_VERSION`)
- Copyright (C) 2022 by nekohasekai
- License: GNU General Public License v3.0 or later, with an additional clause:
  *"no derivative work may use the name or imply association with this
  application without prior consent"* - see
  https://github.com/SagerNet/sing-box/blob/main/LICENSE
- Usage: the `libbox` library (`experimental/libbox`) compiled with `gomobile`
  into `libbox.aar` (Android) and `Libbox.xcframework` (iOS). The binaries are
  not part of the Dart package; they are downloaded at build time from this
  repository's GitHub releases (built from the unmodified sources with
  `scripts/build_libbox.sh`) or built locally with the same script.

Applications that ship libbox distribute GPL-3.0 licensed code and must comply
with its terms, including making the complete corresponding source code
available.

`sing_box` is an unofficial plugin and is not affiliated with SagerNet or the
sing-box project.

## sing-box-for-android / sing-box-for-apple

Parts of the native code are adapted from the official sing-box clients,
licensed under GPL-3.0-or-later:

- https://github.com/SagerNet/sing-box-for-android:
  `android/src/main/kotlin/com/qusadprod/sing_box/core/LibboxRuntime.kt`,
  `service/DefaultNetworkMonitor.kt`, `service/LocalResolver.kt`,
  `service/PlatformInterfaceImpl.kt`, `service/ServiceNotification.kt`,
  `service/SingBoxVpnService.kt`
- https://github.com/SagerNet/sing-box-for-apple:
  `ios/sing_box/Sources/SingBoxTunnel/RunBlocking.swift`,
  `ScreenStateObserver.swift`, `SingBoxPacketTunnelProvider.swift`,
  `SingBoxPlatformInterface.swift`

Each of these files names its origin in its header.
