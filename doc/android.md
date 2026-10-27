# Android guide

This page complements the [README](../README.md#android-setup) with the
details of the Android implementation.

## How it works

* The sing-box core (libbox 1.14.4, `libbox.so`) runs **in your app's main
  process** inside `SingBoxVpnService`, a foreground `VpnService` with the
  `systemExempted` type. No executable is spawned, so there are no
  `useLegacyPackaging`, AAB or SELinux issues.
* The Flutter side talks to the service in-process and to the core through
  the libbox command server (`<filesDir>/command.sock`). Streams reconnect by
  themselves when the service restarts.
* The service state lives in the process, not in the Flutter engine: when the
  Activity (and its engine) is destroyed, the VPN keeps running, and a new
  engine picks up the current status with `initialize()`.
* The last configuration is stored in `<filesDir>/sing-box/last_config.json`
  and is used by Always-on VPN, boot start and the Quick Settings tile.

## Requirements

| | |
| --- | --- |
| minSdk | 24 |
| compileSdk | 36 or newer |
| Android Gradle Plugin | 9.x (built-in Kotlin) |
| JDK for the build | 17 or 21 |

The plugin declares everything it needs in its own manifest:

| Permission | Why |
| --- | --- |
| `INTERNET` | Core sockets |
| `ACCESS_NETWORK_STATE`, `CHANGE_NETWORK_STATE` | Underlying network monitor (`auto_detect_interface`), interface list, connection owner lookup |
| `ACCESS_WIFI_STATE` | Wi-Fi state for `wifi_ssid` / `wifi_bssid` rules |
| `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_SYSTEM_EXEMPTED` | The VPN foreground service |
| `POST_NOTIFICATIONS` | The service notification (runtime permission on Android 13+) |
| `RECEIVE_BOOT_COMPLETED` | `startOnBoot` |

It does **not** declare location or package visibility permissions; add them
yourself when you need the features below.

## Per-app routing and package visibility

`SingBoxRoutingRules.proxyApps`, `bypassApps` and `blockedApps` rely on other
apps being visible to yours. Since Android 11 they are hidden by default:
`VpnService.Builder.addAllowedApplication` then fails and `package_name` rules
never match. Declare either

```xml
<!-- android/app/src/main/AndroidManifest.xml -->
<uses-permission android:name="android.permission.QUERY_ALL_PACKAGES" />
```

or, when you know the packages in advance,

```xml
<queries>
    <package android:name="org.telegram.messenger" />
</queries>
```

`QUERY_ALL_PACKAGES` is restricted on Google Play and has to be justified in
the Play Console.

For safety, a start with a `proxyApps` list of which **no** app is installed
or visible fails with a `SingBoxStartException` instead of silently capturing
every app; packages that cannot be added are logged.

## Notification

```dart
await SingBox.instance.initialize(const SingBoxOptions(
  android: SingBoxAndroidOptions(
    notificationTitle: 'My VPN',
    notificationContent: 'Protected',
    notificationIcon: 'ic_vpn',          // res/drawable/ic_vpn.xml in your app
    showTrafficInNotification: true,     // ↑/↓ speed, paused while the screen is off
    showStopAction: true,
    stopActionTitle: 'Disconnect',
  ),
));
```

* On Android 13+ call `requestNotificationPermission()`; without it the
  service still runs, but the notification is hidden in the drawer.
* The Stop action is hidden automatically while *Always-on VPN* with *Block
  connections without VPN* (lockdown) is active, because stopping would cut
  the device off.

## Permissions flow

* `requestVpnPermission()` shows the system consent dialog through the
  attached Activity and survives configuration changes. If the Activity goes
  away for good, the request resolves with the current permission state.
* Without an Activity it fails with `NO_ACTIVITY`; `connect()` with
  `requestPermission: false` throws `SingBoxPermissionException` instead of
  asking.
* `VpnService.prepare` is per app: if another VPN app is chosen later, the
  system revokes ours and the tunnel stops with
  `android: VPN permission revoked` in `SingBoxConnectionState.error`.

## Always-on VPN, boot start and the Quick Settings tile

* The service declares `SUPPORTS_ALWAYS_ON`. Send users to the system page
  with `openVpnSettings()` to enable *Always-on VPN* / *Block connections
  without VPN*. The system then starts the service with the last
  configuration, also without the Flutter engine.
* `SingBoxSettings.startOnBoot` (or `setServiceOptions(startOnBoot: true)`)
  starts the VPN after `BOOT_COMPLETED` when the VPN permission is granted,
  and after an app update when the VPN was running before.
* `SingBoxSettings.quickSettingsTile` enables a tile that toggles the VPN with
  the last configuration and shows its state; `requestAddQuickSettingsTile()`
  asks the user to add it (Android 13+). When the permission is missing the
  tile opens the app.

## Metered networks

The tunnel declares the real underlying network
(`setUnderlyingNetworks`) and `setMetered(false)`, which on Android means
"metered exactly when the underlying network is": apps see Wi-Fi as unmetered
and mobile data as metered.

## Speed and NAT tests

`runNetworkQualityTest()` / `testSpeed()` and `runStunTest()` run through the
tunnel while it is connected. While it is stopped they test the direct
connection (the outbound tag is ignored).

## App size

libbox adds about 60 MB per ABI (stored uncompressed so it can be memory
mapped and stays 16 KB page aligned, as Google Play requires). A universal
APK with three ABIs is about 235 MB; ship an App Bundle
(`flutter build appbundle`) or split APKs (`flutter build apk --split-per-abi`),
or drop ABIs you do not need:

```kotlin
// android/app/build.gradle.kts
android {
    defaultConfig {
        ndk { abiFilters += listOf("arm64-v8a", "armeabi-v7a") }
    }
}
```

## ProGuard / R8

The plugin ships consumer rules that keep the libbox (`go.**`,
`io.nekohasekai.**`) and plugin classes; release builds with R8 need no extra
configuration.

## Offline builds and mirrors

The libbox AAR (~85 MB) is not part of the pub package. Gradle resolves it
once per machine:

1. Gradle property `singBox.libboxAar` or environment variable
   `SING_BOX_LIBBOX_AAR` - a path to a local AAR;
2. `android/libs/libbox.aar` inside the plugin directory;
3. a download from the GitHub release `libbox-v<version>` into
   `~/.gradle/caches/sing_box/libbox/<version>/`, verified with the SHA-256
   from `android/libbox.properties`. Use `singBox.libboxBaseUrl` /
   `SING_BOX_LIBBOX_BASE_URL` for a mirror.

For CI without internet access, download `libbox.aar` beforehand and set
`SING_BOX_LIBBOX_AAR`, for example in `android/gradle.properties`:

```properties
singBox.libboxAar=/opt/cache/libbox-1.14.4.aar
```

To build libbox yourself see
[Building libbox yourself](../README.md#building-libbox-yourself).

## Troubleshooting

| Symptom | Cause / fix |
| --- | --- |
| `SingBoxStartException: … rule-set …` | A remote rule-set could not be downloaded at the first start. Check the network or point `SingBoxConfigOptions.geoipRuleSetUrl` / `geositeRuleSetUrl` to a reachable mirror, or download through the proxy with `ruleSetDownloadDetour: 'proxy'` |
| `SingBoxStartException: android: none of the include_package apps …` | Package visibility, see above |
| `android: cannot start foreground service` | The start was requested from the background (Android 12+ restrictions). Start the VPN from a visible Activity, the tile, or rely on Always-on VPN |
| Connected but no traffic | Wrong server credentials or an unreachable server; look at `watchLogs()` and `pingOutbound()` |
| `NO_ACTIVITY` | A permission request was made from a background isolate or before the Activity was attached |
| Build fails downloading libbox | Offline or GitHub blocked: use `SING_BOX_LIBBOX_AAR` or a mirror |
