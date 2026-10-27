# sing_box

[![pub package](https://img.shields.io/pub/v/sing_box.svg)](https://pub.dev/packages/sing_box)
[![likes](https://img.shields.io/pub/likes/sing_box)](https://pub.dev/packages/sing_box/score)
[![platform](https://img.shields.io/badge/platform-android%20%7C%20ios-blue)](#platform-support)
[![sing-box](https://img.shields.io/badge/sing--box-1.14.4-informational)](https://github.com/SagerNet/sing-box)

A Flutter VPN plugin powered by [sing-box](https://sing-box.sagernet.org), the
universal proxy platform. It runs the official sing-box core (`libbox`) inside
an Android `VpnService` and an iOS Packet Tunnel Network Extension and exposes
everything a VPN client app needs through a typed Dart API.

```dart
await SingBox.instance.initialize();
await SingBox.instance.connect('vless://…@example.com:443?security=reality&…#My server');
SingBox.instance.watchConnectionStats().listen((s) => print('↓ ${s.downloadSpeed} B/s'));
```

## Features

- **All sing-box protocols**: VLESS (Reality, Vision), VMess, Trojan, Shadowsocks
  (incl. 2022 and plugins), Hysteria / Hysteria2, TUIC, WireGuard, AnyTLS,
  ShadowTLS, SOCKS, HTTP, SSH and more, with WebSocket, gRPC, HTTP/2,
  HTTPUpgrade and QUIC transports, uTLS fingerprints and multiplexing.
- **Share links and subscriptions**: import `vless://`, `vmess://`, `trojan://`,
  `ss://`, `hysteria2://`, `tuic://`, `socks://`, `http://` links and base64
  subscriptions; export profiles back to links.
- **Config generation**: a complete, validated sing-box 1.14 configuration
  (TUN, DNS, routing, URL test groups, cache, clash API) is generated from a
  link or outbound - or bring your own full config.
- **Connection control**: connect, disconnect, reload in place, instant server
  switching without reconnecting, automatic best-server selection (URL test).
- **Live data streams**: status with error reasons and session start time,
  traffic speed and totals, core logs, outbound groups with latencies,
  active connections (close individually), clash mode.
- **Tests**: real latency (HTTP through the proxy, not ICMP), speed test
  (download/upload capacity and responsiveness, RFC-style network quality),
  STUN NAT type / UDP test.
- **Routing rules**: bypass or block apps (Android), domains and subnets,
  "only these apps use the VPN", bypass LAN, bypass whole countries (geoip /
  geosite rule-sets), ad blocking, custom DNS (UDP, TCP, DoT, DoH, DoQ, DoH3).
- **Persistence**: settings, server profiles and routing rules are stored
  natively and applied automatically.
- **Platform integration**: Android foreground notification with live speed
  and a Stop button, Quick Settings tile, start on boot, Always-on VPN support;
  iOS VPN On Demand (auto reconnect) and `includeAllNetworks` kill switch.
- **Diagnostics**: typed exceptions with the exact sing-box error message,
  observer hooks (with a [Talker](https://pub.dev/packages/talker) adapter).

## Platform support

| | Android | iOS |
| --- | --- | --- |
| Minimum version | 7.0 (API 24) | 15.0 |
| VPN mechanism | `VpnService` (foreground service) | Packet Tunnel Network Extension |
| Per-app routing | ✅ | ❌ (requires MDM) |
| Kill switch | System setting (*Block connections without VPN*) | `includeAllNetworks` |
| Auto reconnect | Always-on VPN / sticky service | VPN On Demand |
| Start on boot | ✅ | via On Demand |
| Quick Settings tile | ✅ (Android 7+, add prompt on 13+) | – |
| Simulator / emulator | Emulator: full support | Simulator: UI only, Network Extensions do not run |

The bundled core is **sing-box 1.14.4** built with `with_gvisor`, `with_quic`,
`with_wireguard`, `with_utls`, `with_clash_api` (Apple adds `with_dhcp` and
`with_low_memory`). Tailscale, naive and other heavy components are not
included; see [Building libbox](#building-libbox-yourself).

## Installation

```yaml
dependencies:
  sing_box: ^0.1.0
```

The native libraries (~85 MB AAR, ~200 MB XCFramework) are too large for
pub.dev. They are downloaded automatically on the first build from this
repository's [GitHub releases](https://github.com/QUSAD-prod/sing_box/releases)
and verified with SHA-256:

- **Android**: by Gradle, cached in `~/.gradle/caches/sing_box/`.
- **iOS (Swift Package Manager)**: by SwiftPM as a binary target.
- **iOS (CocoaPods)**: by the podspec during `pod install`, cached in
  `~/Library/Caches/sing_box/`.

Offline or custom builds: see [Using your own libbox build](#using-your-own-libbox-build).

### Android setup

Nothing is required for a basic setup: the plugin declares the VPN service,
the foreground service type, and the permissions it needs (`INTERNET`,
`ACCESS_NETWORK_STATE`, `CHANGE_NETWORK_STATE`, `ACCESS_WIFI_STATE`,
`FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_SYSTEM_EXEMPTED`,
`POST_NOTIFICATIONS`, `RECEIVE_BOOT_COMPLETED`).

Recommended:

1. **minSdk 24** (the Flutter default).
2. **Notification icon**: add a monochrome vector drawable, e.g.
   `android/app/src/main/res/drawable/ic_vpn.xml`, and pass
   `SingBoxAndroidOptions(notificationIcon: 'ic_vpn')`.
3. **App size**: libbox is ~60 MB per ABI. Publish an App Bundle
   (`flutter build appbundle`) or split APKs per ABI
   (`flutter build apk --split-per-abi`); you can also drop ABIs you do not
   need with `ndk { abiFilters += listOf("arm64-v8a", "armeabi-v7a") }`.
4. **Wi-Fi rules**: sing-box rules that match Wi-Fi SSID/BSSID need location
   permissions (`ACCESS_FINE_LOCATION`, and `ACCESS_BACKGROUND_LOCATION` on
   Android 10+), which the plugin intentionally does not declare.

See [doc/android.md](doc/android.md) for details (Always-on VPN, ProGuard,
offline builds).

### iOS setup

A VPN on iOS runs in a separate **Packet Tunnel Network Extension** process,
so the host app needs an extra target. This requires a paid Apple Developer
account (the Network Extension capability is not available to free personal
teams), and VPN tunnels do not run in the iOS Simulator.

1. **App Group** - in the Apple Developer portal (or Xcode → Signing &
   Capabilities) create an App Group, e.g. `group.com.example.myapp`.
2. **Runner target** → *Signing & Capabilities*: add **Network Extensions**
   (check *Packet Tunnel*) and **App Groups** (select your group).
3. **Create the extension**: Xcode → *File → New → Target… → Network
   Extension*, name it `PacketTunnel`, provider type *Packet Tunnel*,
   language Swift. Its bundle id must be `<app bundle id>.PacketTunnel`
   (or pass another one in `SingBoxIosOptions.tunnelBundleIdentifier`). Set
   its deployment target to the same version as Runner (15.0+) and add the
   same two capabilities with the same App Group.
4. **Fix the build phase order** of the Runner target: drag *Embed Foundation
   Extensions* above *Thin Binary* (otherwise Xcode reports
   *"Cycle inside Runner"*).
5. **Link the tunnel library** to the extension target:
   - *Swift Package Manager* (Flutter's default): in the `PacketTunnel` target
     → *General → Frameworks and Libraries* → **+** → choose `SingBoxTunnel`.
   - *CocoaPods*: add to `ios/Podfile` and run `pod install`:
     ```ruby
     target 'PacketTunnel' do
       use_frameworks!
       pod 'SingBoxTunnel', :path => '.symlinks/plugins/sing_box/ios'
     end
     ```
6. **Replace the generated `PacketTunnelProvider.swift`** with:
   ```swift
   import SingBoxTunnel

   class PacketTunnelProvider: SingBoxPacketTunnelProvider {}
   ```
7. In the extension's `Info.plist` add `SingBoxAppGroup` with your App Group id
   (a fallback for system-initiated starts).

The defaults match these conventions (`group.<bundle id>` and
`<bundle id>.PacketTunnel`); otherwise pass them explicitly:

```dart
await SingBox.instance.initialize(const SingBoxOptions(
  ios: SingBoxIosOptions(
    appGroup: 'group.com.example.shared',
    tunnelBundleIdentifier: 'com.example.myapp.VPN',
    profileName: 'My VPN',
  ),
));
```

The example app contains a complete, working setup. See
[doc/ios.md](doc/ios.md) for a scripted setup, troubleshooting and memory
notes.

## Quick start

```dart
import 'package:flutter/material.dart';
import 'package:sing_box/sing_box.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SingBox.instance.initialize(const SingBoxOptions(
    android: SingBoxAndroidOptions(notificationTitle: 'My VPN'),
  ));
  runApp(const MyApp());
}

Future<void> toggleVpn() async {
  final singBox = SingBox.instance;
  if (singBox.status.isActive) {
    await singBox.disconnect();
    return;
  }
  try {
    // A share link, several links, a subscription, an outbound JSON object
    // or a complete sing-box config.
    await singBox.connect('ss://YWVzLTEyOC1nY206cGFzcw@203.0.113.1:8388#Demo');
  } on SingBoxPermissionException {
    // The user declined the VPN permission dialog.
  } on SingBoxConfigException catch (e) {
    // e.message is the exact error reported by sing-box.
  }
}
```

```dart
StreamBuilder<SingBoxConnectionStatus>(
  stream: SingBox.instance.watchConnectionStatus(),
  builder: (context, snapshot) => Text(snapshot.data?.name ?? '…'),
);
```

## Usage guide

### Initialization

Call `initialize()` once before using the API, ideally in `main()`. It sets up
the core, the Android notification channel and the iOS VPN profile, starts
tracking the tunnel state (a tunnel that is already running is picked up
automatically), applies the stored settings and, if
`SingBoxSettings.autoConnectOnStart` is enabled, connects to the active
server.

```dart
await SingBox.instance.initialize(const SingBoxOptions(
  logMaxLines: 3000,
  android: SingBoxAndroidOptions(
    notificationTitle: 'My VPN',
    notificationIcon: 'ic_vpn',
    showTrafficInNotification: true,
    stopActionTitle: 'Disconnect',
  ),
  ios: SingBoxIosOptions(profileName: 'My VPN'),
));
```

### Connecting

`connect()` accepts several kinds of input:

| Input | Result |
| --- | --- |
| A share link (`vless://…`) | Parsed and wrapped into a complete config |
| Several links / a base64 subscription | All servers in a `proxy` selector with an automatic `auto` (URL test) member |
| An outbound JSON object | Wrapped into a complete config |
| A JSON array of outbounds | Same as several links |
| A complete sing-box config | Used as is, with your routing rules applied (`applyRules: false` to disable) |

```dart
await singBox.connect(link);
await singBox.connect(jsonEncode({'type': 'trojan', 'tag': 'tr', 'server': 'example.com', 'server_port': 443, 'password': 'p', 'tls': {'enabled': true}}));
await singBox.connect(myFullConfigJson, applyRules: false);

await singBox.switchServer(otherLink); // reloads in place when connected
await singBox.reload();                // reload the running config
await singBox.restart();               // stop + start
await singBox.disconnect();
```

The final configuration is validated by sing-box before the tunnel starts.
To inspect it without connecting use `buildConfig()`, `checkConfig()`,
`validateConfig()` and `formatConfig()`.

`connect()` completes once the tunnel is **actually connected**. If the core
fails to start (unreachable rule-set, a broken outbound, a revoked
permission, …) it throws a `SingBoxStartException` whose `message` is the
exact sing-box error; if the tunnel is still connecting after `timeout`
(30 s by default) it throws a `SingBoxTimeoutException` and leaves the tunnel
connecting. Pass `waitUntilConnected: false` to return as soon as the start
was requested and follow `watchConnectionState()` instead.

Start and stop requests are executed in order, so rapid toggling always
ends in the state of the last call: a `connect()` that is still waiting when
`disconnect()` or another `connect()` is called throws a
`SingBoxCancelledException` (usually safe to ignore).

`connect()` asks for the VPN permission when needed (pass
`requestPermission: false` to handle it yourself with
`hasVpnPermission()` / `requestVpnPermission()`). On Android 13+ also call
`requestNotificationPermission()` so the VPN notification is visible.

### Status and statistics

```dart
singBox.status;            // cached SingBoxConnectionStatus
singBox.state.startedAt;   // session start
singBox.watchConnectionStatus().listen((status) { … });
singBox.watchConnectionState().listen((state) {
  if (state.error != null) print('Stopped: ${state.error}');
});
singBox.watchConnectionStats().listen((s) {
  print('${s.downloadSpeed} B/s down, ${s.uploadTotal} bytes up, '
      '${s.connectionsOut} connections, session ${s.duration}');
});
await singBox.waitForStatus(SingBoxConnectionStatus.connected);
```

### Server profiles and subscriptions

```dart
final imported = await singBox.importServerConfigs(subscriptionBody, subscriptionId: 'main');
await singBox.setActiveServerConfig(imported.first.id);
await singBox.connectToActiveServer();

final server = SingBoxServerConfig.fromOutbound(outboundJson, name: 'Office');
await singBox.addServerConfig(server);
await singBox.updateServerConfig(server.copyWith(name: 'Office (new)'));
await singBox.removeServerConfig(server.id);
final all = await singBox.getServerConfigs();

final link = SingBoxShareLink.toLink(server.outbound!); // export
```

### Groups, instant switching and latency

Connect with several servers at once to switch between them without
reconnecting and to let sing-box pick the fastest one:

```dart
await singBox.connectToServers(await singBox.getServerConfigs());

singBox.watchGroups().listen((groups) {
  for (final group in groups) {
    print('${group.tag}: ${group.selected}');
    for (final item in group.items) {
      print('  ${item.tag}: ${item.urlTestDelay ?? '-'} ms');
    }
  }
});

await singBox.selectOutbound(SingBoxConfigBuilder.proxyTag, 'Server B');
await singBox.selectOutbound(SingBoxConfigBuilder.proxyTag, SingBoxConfigBuilder.autoTag);
await singBox.urlTest(SingBoxConfigBuilder.proxyTag);           // test every member
final ping = await singBox.pingCurrentServer();                 // SingBoxPingResult
final group = await singBox.testGroup(SingBoxConfigBuilder.proxyTag);
```

Latency is measured with an HTTP request through the proxy
(`SingBoxConfigOptions.urlTestUrl`, default
`https://www.gstatic.com/generate_204`), which reflects real proxy latency.

### Speed and NAT tests

```dart
final result = await singBox.testSpeed();
print('${result.downloadMbps} / ${result.uploadMbps} Mbps');

singBox.runNetworkQualityTest().listen((q) {
  print('${q.phase.name}: ${q.downloadMbps} Mbps, RPM ${q.downloadRpm}');
});

await for (final r in singBox.runStunTest()) {
  print('${r.externalAddress} mapping=${r.natMapping.name}');
}
```

### Routing rules

Rules are stored natively, applied to every generated or user supplied
config, and re-applied to a running tunnel immediately
(`SingBox.reloadOnRulesChange`).

```dart
await singBox.addAppToBypass('com.bank.app');        // Android: not via VPN
await singBox.setProxyApps(['org.telegram.messenger']); // Android: only these via VPN
await singBox.addBlockedApp('com.tracker.app');      // Android: traffic rejected
await singBox.addDomainToBypass('example.ru');
await singBox.addSubnetToBypass('10.0.0.0/8');
await singBox.addBlockedDomain('ads.example.com');
await singBox.setDnsServers(['https://1.1.1.1/dns-query', 'tls://8.8.8.8']);

await singBox.updateRoutingRules((r) => r.copyWith(
  bypassLan: true,
  bypassCountries: ['ru'], // geoip-ru + geosite-ru rule-sets go direct
  blockAds: true,          // geosite-category-ads-all
));
```

### Configuration options

`SingBox.configOptions` controls generated configs:

```dart
SingBox.instance.configOptions = const SingBoxConfigOptions(
  logLevel: SingBoxConfigLogLevel.warn,
  tun: SingBoxTunOptions(mtu: 9000, stack: SingBoxTunStack.mixed, enableIpv6: true),
  dns: SingBoxDnsOptions(remote: 'https://1.1.1.1/dns-query', strategy: SingBoxDnsStrategy.preferIpv4),
  urlTestInterval: Duration(minutes: 3),
  enableClashModes: true,
);
```

Use `SingBoxConfigBuilder` directly to generate configs without connecting:

```dart
final builder = SingBoxConfigBuilder(options);
final config = builder.build([SingBoxShareLink.parse(link).json], rules: rules);
final patched = builder.apply(userConfig, rules: rules);
```

### Clash modes, connections, logs

```dart
singBox.watchClashMode().listen((m) => print('${m.current} of ${m.modes}'));
await singBox.setClashMode('Global'); // Rule / Global / Direct

singBox.watchConnections().listen((list) { … });
await singBox.closeConnection(id);
await singBox.closeAllConnections();

singBox.watchLogBuffer(maxEntries: 1000).listen((entries) { … });
singBox.watchLogs().where((e) => e.level.isAtLeast(SingBoxLogLevel.warn)).listen(print);
await singBox.clearLogs();

singBox.watchNotifications().listen((n) => print(n.title)); // core notifications
```

### Settings

```dart
await singBox.saveSettings(const SingBoxSettings(
  autoConnectOnStart: true,          // connect to the active server on app start
  autoReconnectOnDisconnect: true,   // iOS: VPN On Demand
  killSwitch: true,                  // iOS: includeAllNetworks
  startOnBoot: true,                 // Android
  quickSettingsTile: true,           // Android
));
await singBox.updateSetting(SingBoxSettings.keyKillSwitch, false);
await singBox.openVpnSettings();     // Android: Always-on VPN / Block connections without VPN
await singBox.requestAddQuickSettingsTile(); // Android 13+
```

### Error handling

Every failure is a `SingBoxException` with a `code`:

| Exception | When |
| --- | --- |
| `SingBoxConfigException` | Invalid input or the config was rejected by sing-box (message = sing-box error) |
| `SingBoxPermissionException` | VPN permission / profile not granted |
| `SingBoxStartException` | The tunnel failed to start or stopped before it connected (message = sing-box error) |
| `SingBoxTimeoutException` | `connect()` timed out while the tunnel was still connecting |
| `SingBoxCancelledException` | A waiting `connect()` was superseded by `disconnect()` or another `connect()` |
| `SingBoxServiceNotRunningException` | The operation needs a running tunnel |
| `SingBoxUnsupportedException` | Not available on this platform |
| `SingBoxNotInitializedException` | `initialize()` was not called |

Runtime failures that stop the tunnel are reported in
`SingBoxConnectionState.error`.

### Logging

```dart
class MyObserver extends SingBoxObserver {
  @override
  void error(String message, [Object? error, StackTrace? stackTrace]) =>
      debugPrint('[sing_box] $message: $error');
}

SingBox.instance.setObserver(MyObserver());
// or with Talker:
SingBox.instance.setObserver(SingBoxTalkerObserver(talker));
```

### Testing your app

`SingBoxPlatform.instance` can be replaced with a fake in unit tests:

```dart
class FakeSingBox extends SingBoxPlatform with MockPlatformInterfaceMixin { … }

setUp(() => SingBoxPlatform.instance = FakeSingBox());
```

See `test/support/fake_platform.dart` in this repository for a complete
in-memory implementation.

## Supported share links

| Scheme | Notes |
| --- | --- |
| `vless://` | TLS / Reality (`pbk`, `sid`, `spx`), Vision flow, `tcp`, `ws`, `grpc`, `http`/`h2`, `httpupgrade`, uTLS `fp`. XHTTP is not supported by sing-box. |
| `vmess://` | v2rayN base64 JSON format |
| `trojan://` | TLS, transports as VLESS |
| `ss://` | SIP002 and legacy formats, `obfs-local` / `v2ray-plugin` |
| `hysteria2://`, `hy2://` | obfs `salamander`, port hopping, bandwidth |
| `hysteria://` | v1 |
| `tuic://` | v5 |
| `socks://`, `socks5://`, `http://`, `https://` | Plain proxies |

## Building libbox yourself

```bash
scripts/build_libbox.sh android apple --install
```

The script fetches the sing-box version from `LIBBOX_VERSION`, installs
SagerNet's `gomobile` and builds `build/libbox/libbox.aar` and
`build/libbox/Libbox.xcframework(.zip)` with SHA-256 files. `--install` copies
them into the plugin so local builds skip the download. Requirements: Go 1.25+,
Android SDK + NDK, JDK 17/21, Xcode. Set `LIBBOX_TAGS` to change the compiled
features.

### Using your own libbox build

- Android: set the Gradle property `singBox.libboxAar=/path/to/libbox.aar`
  (in `android/gradle.properties`) or the environment variable
  `SING_BOX_LIBBOX_AAR`.
- iOS: put `Libbox.xcframework` into the plugin's `ios/sing_box/Frameworks/`
  (for a pub dependency: `.symlinks/plugins/sing_box/ios/sing_box/Frameworks/`),
  or point downloads to a mirror with `SING_BOX_LIBBOX_BASE_URL`.

## Troubleshooting

- **Android: VPN starts but there is no traffic** - check the logs
  (`watchLogs()`); most often the server is unreachable or the credentials are
  wrong. `checkConfig()` reports configuration errors with the exact sing-box
  message.
- **Android: the notification is not shown** - request
  `requestNotificationPermission()` on Android 13+.
- **iOS: `requestVpnPermission()` fails** - the Network Extension capability,
  the App Group or the extension bundle id do not match. The Runner and the
  extension must be signed by the same team and share the App Group.
- **iOS: "Cycle inside Runner"** - move *Embed Foundation Extensions* above
  *Thin Binary* in the Runner build phases.
- **iOS: the extension is killed under load** - Network Extensions are limited
  to about 50 MB of memory. The bundled core is built for low memory use;
  avoid huge rule-sets and keep `disableMemoryLimit` off.
- **The first build is slow** - the native library is downloaded once and
  cached.

## Migrating from 0.0.x

0.1.0 is a rewrite on top of sing-box 1.14:

- Action methods (`connect`, `disconnect`, …) return `Future<void>` and throw
  `SingBoxException`s instead of returning `false`.
- `watchSingBoxConnectionStatus` / `watchSingBoxConnectionStats` /
  `getActiveSingBoxServerConfig` are deprecated in favour of
  `watchConnectionStatus` / `watchConnectionStats` / `getActiveServerConfig`.
- `SingBoxConnectionStatus` has four values (`disconnected`, `connecting`,
  `connected`, `disconnecting`); the failure reason is in
  `SingBoxConnectionState.error`.
- `SingBoxConnectionStats` uses `uploadSpeed`, `downloadSpeed`,
  `uploadTotal`, `downloadTotal`, `duration` (old names are deprecated getters).
- Routing lists moved from `SingBoxSettings` to `SingBoxRoutingRules`.
  "Blocked" apps/domains are now really blocked; use the bypass lists to
  exclude them from the VPN.
- iOS needs the Packet Tunnel extension target described above.

## License

The Dart and native wrapper code of this plugin is released under the
[MIT License](LICENSE). The bundled sing-box core (`libbox`) is licensed under
**GPL-3.0-or-later**; apps that ship it must comply with the GPL. See
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

This project is not affiliated with SagerNet or the sing-box project.
