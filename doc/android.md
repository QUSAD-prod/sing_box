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
| compileSdk | 35 or newer |
| Android Gradle Plugin | 9.x (built-in Kotlin), or 8.7+ with the Kotlin Android plugin 1.8.22+ (applied by the plugin when built-in Kotlin is off) |
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

## Proxy-only mode (no VPN)

A configuration **without a TUN inbound** runs without the VPN: no VPN
permission, no VPN key icon, and the core only serves its local proxy
inbounds. Generate one with
`SingBoxConfigOptions(inboundMode: SingBoxInboundMode.proxyOnly)` (a `mixed`
HTTP + SOCKS5 inbound on `127.0.0.1:2080`, see `localProxy`) or connect with
a complete configuration without `tun`. Apps then use the proxy through their
own settings (Wi-Fi proxy, browser or app settings).

It runs in `SingBoxProxyService`, a foreground service of the `specialUse`
type (like the ProxyService of sing-box-for-android). The plugin does **not**
declare it, so apps that only use the VPN need no `specialUse` declaration on
Google Play. To use the mode, declare it in your app's
`android/app/src/main/AndroidManifest.xml` (compileSdk 34+):

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_SPECIAL_USE" />
    <application>
        <service
            android:name="com.qusadprod.sing_box.service.SingBoxProxyService"
            android:exported="false"
            android:foregroundServiceType="specialUse">
            <property
                android:name="android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE"
                android:value="proxy" />
        </service>
    </application>
</manifest>
```

Without it `connect()` throws a `SingBoxUnsupportedException`. Google Play
asks for a description of the `specialUse` foreground service.

* The notification, the Quick Settings tile, `startOnBoot`, the streams and
  the commands work as with the VPN.
* Not available without the VPN: per-app routing, bypassed subnets
  (`route_exclude_address`), Always-on VPN, `allowBypass`, the system proxy
  and the latency probe routes (latency tests use sing-box's URL test, TCP and
  ICMP pings work as usual).
* Switching between a VPN and a proxy-only configuration restarts the core
  (`connect()` does it; a `reload` cannot switch).
* The proxy has no authentication: every app on the device can use it.

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
  configuration (after boot and after app updates), also without the Flutter
  engine. Under *Block connections without VPN* the notification has no Stop
  action, since stopping would cut the device off.
* `SingBoxSettings.startOnBoot` (or `setServiceOptions(startOnBoot: true)`)
  starts the VPN after `BOOT_COMPLETED` when the VPN permission is granted,
  and after an app update when the VPN was running before.
* `SingBoxSettings.quickSettingsTile` enables a tile that toggles the VPN with
  the last configuration and shows its state; `requestAddQuickSettingsTile()`
  asks the user to add it (Android 13+). When the permission is missing the
  tile opens the app. The system refreshes the tile while the Quick Settings
  panel is open.
* Closing the app (Back, swiping it away from Recents) keeps the VPN
  running; when the app is opened again `initialize()` reports the running
  tunnel as `connected`.
* Configurations with `wifi_ssid` / `wifi_bssid` rules need location
  permissions to read the Wi-Fi name; after a boot or Always-on start (no
  visible Activity) Android only grants that with background location access.

### Checking the lifecycle on a device

`example/lib/e2e_harness.dart` is a tiny entry point for these scenarios. It
connects through a `direct` outbound (no server needed) and prints every state
change to logcat:

```bash
cd example
flutter build apk --debug -t lib/e2e_harness.dart \
  --dart-define=HARNESS_ACTION=connect \
  --dart-define=HARNESS_TILE=true --dart-define=HARNESS_START_ON_BOOT=true
adb install -r build/app/outputs/flutter-apk/app-debug.apk
adb shell am start -n com.qusadprod.sing_box_example/.MainActivity
adb logcat -s flutter | grep SING_BOX_HARNESS

# Quick Settings tile (open the panel first so the tile shows the current state)
TILE=com.qusadprod.sing_box_example/com.qusadprod.sing_box.service.SingBoxTileService
adb shell cmd statusbar add-tile $TILE
adb shell cmd statusbar expand-settings
adb shell cmd statusbar click-tile $TILE

# Boot start; is the tunnel up?
adb reboot
adb shell ip addr show tun0
```

On an emulator Always-on VPN with lockdown can be set with
`adb shell settings put secure always_on_vpn_app com.qusadprod.sing_box_example`
and `adb shell settings put secure always_on_vpn_lockdown 1` followed by a
reboot (wait a few seconds after `settings put`, the value is written lazily).

## Metered networks

The tunnel declares the real underlying network
(`setUnderlyingNetworks`) and `setMetered(false)`, which on Android means
"metered exactly when the underlying network is": apps see Wi-Fi as unmetered
and mobile data as metered.

## Speed and NAT tests

`runNetworkQualityTest()` / `testSpeed()` and `runStunTest()` run through the
tunnel while it is connected. While it is stopped they test the direct
connection (the outbound tag is ignored).

## Latency tests and the start

* `connect()` reports `connected` once Android routes the app itself
  through the VPN (`establish()` returns earlier; a connection opened in
  between would leave through the underlying network). The service waits at
  most 3 s and not at all when the app is excluded from the tunnel.
* While the VPN is stopped, `pingServers()` with a proxy method starts a
  second libbox service in the app process (no TUN, inbounds on
  `127.0.0.1`); its sockets are protected from a running VPN.
* `tcp` / `icmp` use `android.system.Os` sockets: the name is resolved on
  the underlying network and the sockets are protected while the VPN runs.
  ICMP uses unprivileged ping sockets (`SOCK_DGRAM`); on the emulator the
  emulator itself answers, so the numbers are not meaningful there.
* Rules with `wifi_ssid` / `wifi_bssid` need the location permission
  (`ACCESS_BACKGROUND_LOCATION` on Android 10+, which the plugin does not
  declare); without it the core log shows a warning and these rules do not
  match.

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

## sing-box-lx core

`sing_box: core: lx` in the app's `pubspec.yaml` (next to the app's
`android/` directory), the environment variable `SING_BOX_CORE=lx` or the
Gradle property `singBox.core=lx` link the sing-box-lx libbox (README
"sing-box-lx core"). Gradle then reads the `lx.*` keys of
`android/libbox.properties`, uses `android/libs/libbox-lx.aar` as the local
copy and compiles `src/core-lx/kotlin` instead of `src/core-standard/kotlin`:
the lx libbox adds members to its interfaces (`CommandClientHandler
.writeDNSQuery`), so the classes implementing them get a per-core base class
there. The lx AAR is ~4 MB larger than the standard one.

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
