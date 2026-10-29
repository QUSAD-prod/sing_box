# sing_box

[![pub package](https://img.shields.io/pub/v/sing_box.svg)](https://pub.dev/packages/sing_box)
[![likes](https://img.shields.io/pub/likes/sing_box)](https://pub.dev/packages/sing_box/score)
[![platform](https://img.shields.io/badge/platform-android%20%7C%20ios-blue)](#platform-support)
[![sing-box](https://img.shields.io/badge/sing--box-1.14.4-informational)](https://github.com/SagerNet/sing-box)
[![license](https://img.shields.io/badge/license-GPL--3.0--or--later-blue)](#license)

A Flutter VPN plugin powered by [sing-box](https://sing-box.sagernet.org), the
universal proxy platform. It runs the official sing-box core (`libbox`) inside
an Android `VpnService` and an iOS Packet Tunnel Network Extension and exposes
everything a VPN client app needs through a typed Dart API.

> **Unofficial.** This plugin is a community project. It is not affiliated
> with, endorsed by or supported by SagerNet or the sing-box project; report
> problems with the plugin [here](https://github.com/QUSAD-prod/sing_box/issues).

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
  `ss://`, `hysteria2://`, `hysteria://`, `tuic://`, `anytls://`,
  `wireguard://`, `socks://`, `http://` links and base64, plain, sing-box
  JSON, SIP008 and **Clash / mihomo YAML** subscriptions; export profiles
  back to links.
- **Subscriptions by URL**: download and refresh subscriptions with traffic
  used, limit and expiry (`subscription-userinfo`), provider name, update
  interval and links; automatic updates of stale subscriptions.
- **Config generation**: a complete, validated sing-box 1.14 configuration
  (TUN, DNS, routing, URL test groups, cache, clash API) is generated from a
  link or outbound - or bring your own full config.
- **Connection control**: connect, disconnect, reload in place, instant server
  switching without reconnecting, automatic best-server selection (URL test).
- **Live data streams**: status with error reasons and session start time,
  traffic speed and totals, core logs, outbound groups with latencies,
  active connections (close individually), clash mode.
- **Tests**: latency by HTTP `HEAD`/`GET` through the proxy (also while disconnected and for UDP protocols), TCP handshake or ICMP, speed test
  (download/upload capacity and responsiveness, RFC-style network quality),
  STUN NAT type / UDP test.
- **Routing rules**: everything through the VPN or **only the listed
  resources** (e.g. sites blocked in Russia); proxy, bypass or block apps
  (Android), domains and subnets, "only these apps use the VPN", bypass LAN,
  bypass whole countries (geoip / geosite rule-sets), ordered **custom rules**
  (domains, keywords, regexes, IPs, ports, apps, rule-sets by tag or URL,
  protocols), QUIC blocking, BitTorrent directly, ad blocking, custom DNS
  (UDP, TCP, DoT, DoH, DoQ, DoH3), IP version: IPv4 and IPv6, IPv4 only or
  IPv6 only; JSON export / import.
- **Reliable rule-sets**: the plugin downloads rule-sets itself (with
  jsDelivr mirrors) and the core reads local files, so a blocked or slow
  rule-set host never stops the VPN from starting.
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
| Auto reconnect | Always-on VPN | VPN On Demand |
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
  sing_box: ^1.1.0
```

Requires Flutter 3.29 or newer (Dart 3.7+).

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

1. **minSdk 24**: the Flutter default since 3.35. Apps created with older
   Flutter versions set `minSdk = 24` in `android/app/build.gradle(.kts)`.
   Both AGP 9 (built-in Kotlin) and AGP 8 with the Kotlin Android plugin
   1.8.22+ are supported.
2. **Notification icon**: add a monochrome vector drawable, e.g.
   `android/app/src/main/res/drawable/ic_vpn.xml`, and pass
   `SingBoxAndroidOptions(notificationIcon: 'ic_vpn')`.
3. **App size**: libbox is ~60 MB per ABI. Publish an App Bundle
   (`flutter build appbundle`) or split APKs per ABI
   (`flutter build apk --split-per-abi`); you can also drop ABIs you do not
   need with `ndk { abiFilters += listOf("arm64-v8a", "armeabi-v7a") }`.
4. **Per-app routing** (`proxyApps`, `bypassApps`, `blockedApps`): on
   Android 11+ other apps are invisible unless you declare
   `QUERY_ALL_PACKAGES` or list them in `<queries>`; see
   [doc/android.md](doc/android.md#per-app-routing-and-package-visibility).
5. **Wi-Fi rules**: sing-box rules that match Wi-Fi SSID/BSSID need location
   permissions (`ACCESS_FINE_LOCATION`, and `ACCESS_BACKGROUND_LOCATION` on
   Android 10+), which the plugin intentionally does not declare.

See [doc/android.md](doc/android.md) for details (Always-on VPN, Quick
Settings tile, ProGuard, offline builds, troubleshooting).

### iOS setup

A VPN on iOS runs in a separate **Packet Tunnel Network Extension** process,
so the host app needs an extra target. This requires a paid Apple Developer
account (the Network Extension capability is not available to free personal
teams), and VPN tunnels do not run in the iOS Simulator.

1. **Add the extension target** with the plugin's setup tool (run it in your
   app directory; no Ruby or CocoaPods needed):
   ```bash
   flutter build ios --config-only
   dart run sing_box:setup_ios
   ```
   It creates `ios/PacketTunnel/` (a provider that is just
   `class PacketTunnelProvider: SingBoxPacketTunnelProvider {}`, `Info.plist`,
   entitlements), adds the Network Extension and App Group entitlements to
   Runner and embeds the extension *before* Flutter's *Thin Binary* phase (no
   *"Cycle inside Runner"*). The extension gets the plugin's `SingBoxTunnel`
   library through Flutter's Swift package when Flutter links plugins with
   Swift Package Manager (the default since Flutter 3.44: **no Podfile
   needed**), or through `pod 'SingBoxTunnel'` in `ios/Podfile` with
   CocoaPods. Re-running it is safe. Options: `--bundle-id`, `--app-group`,
   `--team`, `--target`, `--project`.
2. **Capabilities**: in the Apple Developer portal enable *Network
   Extensions* and *App Groups* (`group.<app bundle id>` by default) for both
   `<app bundle id>` and `<app bundle id>.PacketTunnel`, or let Xcode's
   automatic signing do it.
3. **Deployment target 15.0**: older Flutter versions create apps for an
   earlier iOS (Flutter 3.29: iOS 12.0); set *Minimum Deployments* of Runner
   to 15.0 (or `IPHONEOS_DEPLOYMENT_TARGET = 15.0` in
   `ios/Runner.xcodeproj/project.pbxproj`).
4. Build as usual (`flutter build ios` / `flutter run`).

The manual steps are described in [doc/ios.md](doc/ios.md#manual-setup).

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
[doc/ios.md](doc/ios.md) for the manual setup, how the tunnel works,
troubleshooting and memory notes.

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

### Server profiles

```dart
final imported = await singBox.importServerConfigs(linksOrSubscriptionBody);
await singBox.setActiveServerConfig(imported.first.id);
await singBox.connectToActiveServer();

final server = SingBoxServerConfig.fromOutbound(outboundJson, name: 'Office');
await singBox.addServerConfig(server);
await singBox.updateServerConfig(server.copyWith(name: 'Office (new)'));
await singBox.removeServerConfig(server.id);
final all = await singBox.getServerConfigs();

final link = SingBoxShareLink.toLink(server.outbound!); // export
```

### Subscriptions

`addSubscription()` downloads a subscription URL, imports its servers as
profiles (their `subscriptionId` is the subscription id) and stores the
subscription with the metadata the provider sends in its response headers:

```dart
final sub = await singBox.addSubscription(
  'https://example.com/sub/token',
  name: 'My provider',              // optional: else profile-title or the host
  headers: {'x-hwid': deviceId},    // optional extra request headers
);
print('${sub.name}: ${sub.serverCount} servers');
print('traffic ${sub.used} / ${sub.total} bytes, expires ${sub.expire}');

await singBox.updateSubscription(sub.id);               // download again
await singBox.updateSubscriptions(onlyStale: true);     // e.g. on app resume
await singBox.editSubscription(sub.copyWith(updateInterval: const Duration(hours: 6)));
await singBox.removeSubscription(sub.id);               // and its servers

singBox.watchSubscriptions().listen((subs) { … });
```

| `SingBoxSubscription` field | Source |
| --- | --- |
| `upload`, `download`, `total`, `expire` (and `used`, `remaining`, `isExpired`) | `subscription-userinfo` |
| `name` | your `name`, else `profile-title` (plain or `base64:`), else the `content-disposition` file name, else the URL host |
| `providerUpdateInterval` | `profile-update-interval` (hours); `updateInterval` overrides it, default 24 h |
| `webPageUrl`, `supportUrl`, `announce` | `profile-web-page-url`, `support-url`, `announce` |
| `lastUpdated`, `lastError`, `serverCount` | the last update |

* **Formats**: share links (plain or base64), a sing-box configuration or
  outbound list, SIP008 and Clash / mihomo YAML (see
  [Supported subscription formats](#supported-subscription-formats)).
* **User-Agent**: many providers choose the format by it. The default is
  `sing-box/<core version>`; change it for all subscriptions with
  `SingBox.subscriptionUserAgent` or per subscription with `userAgent`.
* **Updates**: `initialize()` refreshes subscriptions with `autoUpdate`
  that are older than their interval; call `updateSubscriptions(onlyStale:
  true)` again when the app returns to the foreground. An update replaces
  the subscription's servers; servers keep their id
  (`<subscription id>/<server name>`) and `enabled` flag when the provider
  keeps their names, so the active server stays selected. A running tunnel
  is not reloaded.
* **Errors**: a failed download or a body without supported servers throws
  `SingBoxSubscriptionException` (with `statusCode` for HTTP errors); for
  updates it is also stored in `lastError` and the old servers are kept.

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

#### Latency (ping)

Four ways to measure a server (`SingBoxPingMethod`):

| Method | What is measured | Works for | Tunnel |
| --- | --- | --- | --- |
| `proxyHead` (default) | `HEAD` of `SingBoxConfigOptions.urlTestUrl` through the server, until the response headers arrive | every protocol, UDP based ones included | through it, or a temporary core while stopped |
| `proxyGet` | the same with `GET` | every protocol | same |
| `tcp` | TCP handshake with the server | TCP based protocols (not Hysteria, TUIC, WireGuard, QUIC transports) | bypasses it |
| `icmp` | one ICMP echo | servers that answer ping | bypasses it |

```dart
final current = await singBox.pingCurrentServer();                    // proxyHead
final viaGet = await singBox.pingOutbound('Server B', method: SingBoxPingMethod.proxyGet);
final servers = await singBox.getServerConfigs();
singBox.pingServers(servers, method: SingBoxPingMethod.tcp, concurrency: 8).listen((r) {
  print('${r.serverId}: ${r.success ? '${r.ping} ms' : r.errorMessage}');
});
```

How it works:

* **Connected**: generated and applied configurations contain probe routes:
  a connection from the app to `198.51.100.1:20000+i`
  (`SingBoxConfigOptions.probeAddress`, an unused TEST-NET address) goes
  through outbound `i` to the host of `urlTestUrl`. The app sends the
  request itself, so no local port is opened. Without probe routes (a
  complete config of your own, or the app excluded from the tunnel)
  sing-box's URL test of the outbound is used. `pingServers()` measures the
  profiles of the running configuration and fails the others; connect with
  `connectToServers()` to measure them all.
* **Stopped**: `pingServers()` starts a temporary core in the app (no TUN,
  inbounds on `127.0.0.1`, at most 64 profiles at a time), measures and
  stops it. This also gives real latency for UDP based protocols.
* **TCP / ICMP** are measured natively outside the tunnel; the server name is
  resolved by the underlying network, not by the tunnel's DNS (FakeIP).
  Android protects the sockets from the VPN; iOS measures in the Packet
  Tunnel extension while the tunnel runs. ICMP numbers on emulators are not
  meaningful (the emulator answers itself).

Results carry `method`, `url` and the HTTP `statusCode` (proxy methods).
`SingBoxPingMethod.urlTest` is a deprecated alias of `proxyHead`.

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
  blockQuic: true,         // apps fall back to TCP
  bittorrentDirect: true,  // torrents never use the VPN
));

await singBox.setIpVersion(SingBoxIpVersion.ipv4); // IPv4 only
```

**Routing mode** (`SingBoxRoutingRules.mode`) decides where traffic that no
rule matches goes. The lists work in both modes:

| Mode | Unmatched traffic | Typical use |
| --- | --- | --- |
| `SingBoxRoutingMode.proxyAll` (default) | through the proxy | "everything via VPN", optionally `bypassCountries: ['ru']` for "everything except Russian sites" |
| `SingBoxRoutingMode.proxyListed` | directly, resolved by the direct DNS server | "only blocked sites via VPN" with `blockedInCountries` / `proxyDomains` / `proxySubnets` |

```dart
// Only sites blocked in Russia (and example.org) use the VPN.
await singBox.setRoutingMode(SingBoxRoutingMode.proxyListed);
await singBox.updateRoutingRules(
  (r) => r.copyWith(blockedInCountries: ['ru']),
);
await singBox.addProxyDomain('example.org');
await singBox.addProxySubnet('203.0.113.0/24');
```

`blockedInCountries` supports `ru` (domains and IP ranges blocked in Russia
from [runetfreedom/russia-v2ray-rules-dat](https://github.com/runetfreedom/russia-v2ray-rules-dat))
and `cn` (sites outside mainland China). `bypassCountries: ['ru']` also
connects the sites that only work from inside Russia directly.

Rules are evaluated in this order: blocked apps, domains and ads → QUIC /
BitTorrent → Clash modes → custom rules → proxy lists → LAN → bypass lists →
the mode. A proxied list wins over a bypassed one: a blocked site on a
Russian IP address still uses the VPN when Russian sites are bypassed.

**Custom rules** (`SingBoxRoutingRule`) are evaluated in list order before
the presets. Destination conditions (domains, suffixes, keywords, regexes,
IP CIDRs, rule-sets) are alternatives; ports, apps, network and protocols
must match as well. Invalid entries are dropped, and a rule whose condition
has no valid entry left is skipped rather than matching too much.

```dart
await singBox.setCustomRules([
  const SingBoxRoutingRule(
    action: SingBoxRuleAction.direct,
    domainSuffixes: ['corp.example.com'],
    ipCidrs: ['10.20.0.0/16'],
  ),
  const SingBoxRoutingRule(
    action: SingBoxRuleAction.proxy,
    ruleSets: ['geosite-youtube', 'https://example.com/my-list.srs'],
  ),
  const SingBoxRoutingRule(
    action: SingBoxRuleAction.block,
    ports: ['25', '6881-6889'],
    network: SingBoxRuleNetwork.tcp,
  ),
]);

final json = await singBox.exportRoutingRules(); // backup / share
await singBox.importRoutingRules(json);
```

Rule-sets are SagerNet geosite / geoip tags (`geosite-youtube`, `geoip-us`,
see `SingBoxRuleSets`) or `https://` URLs of binary (`.srs`) or source
(`.json`) rule-sets. Protocol conditions (`quic`, `bittorrent`, `stun`, …)
need sniffing (`SingBoxConfigOptions.sniff`, on by default).

**Rule-set downloads.** sing-box aborts the start when it cannot download a
remote rule-set the first time. So the plugin downloads the rule-sets
itself into the working directory (trying jsDelivr mirrors when GitHub is
unreachable), and generated configs read local files. If a rule-set cannot
be downloaded, the rules that need it are left out and the VPN still
starts. Outdated files (`SingBoxConfigOptions.ruleSetUpdateInterval`) are
refreshed in the background on connect and on app start, and a running
tunnel picks them up by itself.

```dart
for (final ruleSet in await singBox.getRuleSets()) {
  print('${ruleSet.tag}: ${ruleSet.lastError ?? ruleSet.updatedAt}');
}
await singBox.updateRuleSets(force: true); // download again now
singBox.manageRuleSets = false; // let sing-box download remote rule-sets
```

**IP version** (`SingBoxRoutingRules.ipVersion`):

| Value | Effect |
| --- | --- |
| `SingBoxIpVersion.dual` (default) | IPv4 and IPv6; the preferred family is `SingBoxDnsOptions.strategy` (IPv4 first by default) |
| `SingBoxIpVersion.ipv4` | Names resolve to IPv4 only (`ipv4_only`) and IPv6 connections that would go through the proxy are rejected, so apps fall back to IPv4 at once. The TUN keeps its IPv6 address, so IPv6 traffic does not leak outside the VPN. Use it when the server or the network has no working IPv6. |
| `SingBoxIpVersion.ipv6` | Names resolve to IPv6 only (`ipv6_only`); sites without IPv6 cannot be opened by name, IPv4 addresses still work |

For user supplied configurations `dual` changes nothing; the other values
set `dns.strategy` and (IPv4 only) append the IPv6 reject rule after the
config's own rules.

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

#### Proxy-only mode (Android)

`inboundMode: SingBoxInboundMode.proxyOnly` generates a configuration without
a TUN: no VPN and no VPN permission, only the local proxy (`localProxy`,
default `127.0.0.1:2080`) that apps use through their proxy settings. The app
declares the `specialUse` foreground service for it - see
[doc/android.md](doc/android.md#proxy-only-mode-no-vpn). iOS cannot run the
core without the VPN and throws `SingBoxUnsupportedException`.

```dart
SingBox.instance.configOptions = const SingBoxConfigOptions(
  inboundMode: SingBoxInboundMode.proxyOnly,
  localProxy: SingBoxLocalProxy(port: 2080),
);
await singBox.connectToActiveServer(); // no VPN permission dialog
```

#### Local proxy and system proxy

`localProxy` adds a local HTTP + SOCKS5 proxy (sing-box `mixed` inbound) next
to the TUN; with `systemProxy: true` the VPN also announces it as the system
HTTP proxy (Android 10+, iOS). Apps that honour the system proxy (browsers,
most HTTP clients) then reach it directly instead of through the TUN, which
saves a round of packet processing; all other traffic still uses the TUN.

```dart
SingBox.instance.configOptions = const SingBoxConfigOptions(
  localProxy: SingBoxLocalProxy(
    port: 2080,                   // 127.0.0.1:2080, HTTP and SOCKS5
    systemProxy: true,            // TUN platform.http_proxy
    bypassDomains: ['example.com'],
  ),
);

// While connected: the "System proxy" switch of the official clients.
final status = await singBox.getSystemProxyStatus(); // available / enabled
await singBox.setSystemProxyEnabled(false); // remembered on the device
```

The proxy has no authentication, so every app on the device can use it while
the VPN runs. Android applies `setSystemProxyEnabled()` by reloading the
tunnel; iOS updates the tunnel's network settings in place.

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
  allowBypass: false,                // Android: apps may bind to another network and leave the VPN
));
await singBox.updateSetting(SingBoxSettings.keyKillSwitch, false);
await singBox.openVpnSettings();     // Android: Always-on VPN / Block connections without VPN
await singBox.requestAddQuickSettingsTile(); // Android 13+
```

#### Memory limit (OOM killer)

sing-box can watch its own memory and reset the network (close connections
and free memory) before the system kills it. `oomKiller` and `memoryLimitMb`
are applied when the tunnel starts - reconnect after changing them:

```dart
await singBox.updateSetting(
  SingBoxSettings.keyOomKiller,
  SingBoxOomKiller.reportOnly, // only write out-of-memory reports
);
await singBox.updateSetting(SingBoxSettings.keyMemoryLimitMb, 300);
```

| `SingBoxOomKiller` | Behaviour |
| --- | --- |
| `platformDefault` | iOS: `enabled` (the Network Extension is killed above ~50 MB). Android: `off`, like sing-box-for-android |
| `off` | No monitoring, no Go memory limit |
| `reportOnly` | Monitors and writes reports (`getCoreReports()`), never closes connections |
| `enabled` | Monitors, resets the network at the limit and writes reports |

`memoryLimitMb` (`0` = default) sets the limit; the Go garbage collector
targets 80 % of it. Android without a limit reacts to low available system
memory. iOS: the monitor of the extension always uses the system limit
(50 MB), a different value only moves the garbage collector target.

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
| `SingBoxSubscriptionException` | A subscription could not be downloaded or had no supported servers |

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
| `vmess://` | v2rayN base64 JSON, Xray and Shadowrocket formats |
| `trojan://` | TLS, transports as VLESS |
| `ss://` | SIP002, SIP022 (2022 ciphers) and legacy formats, `obfs-local` / `v2ray-plugin` |
| `hysteria2://`, `hy2://` | obfs `salamander`, port hopping, bandwidth |
| `hysteria://` | v1 |
| `tuic://` | v5 |
| `anytls://` | AnyTLS |
| `wireguard://`, `wg://` | WireGuard endpoint |
| `socks://`, `socks5://`, `socks5h://`, `socks4://`, `http://`, `https://` | Plain proxies |

`ssr://` (ShadowsocksR), XHTTP and mKCP transports are not supported by
sing-box; such links fail with a `FormatException` that says so.

## Supported subscription formats

`SingBoxShareLink.parseSubscription()`, `importServerConfigs()` and
`addSubscription()` detect the format automatically:

| Format | Notes |
| --- | --- |
| Share links | One per line, plain or base64 (standard or URL-safe, also per line) |
| sing-box JSON | A complete configuration (its proxy outbounds and endpoints are taken) or an outbound array |
| SIP008 | Shadowsocks `{"servers": [...]}` |
| Clash / mihomo YAML | The `proxies` list; `proxy-groups`, `rules` and `dns` are ignored |

Clash / mihomo proxy types and options:

| `type` | Converted options |
| --- | --- |
| `ss` | ciphers incl. 2022, `plugin: obfs` / `v2ray-plugin` (websocket), `udp-over-tcp` |
| `vmess` | `cipher`, `alterId`, `tls`, `servername`, `global-padding`, `authenticated-length`, `packet-encoding` |
| `vless` | `flow: xtls-rprx-vision`, `tls`, `reality-opts`, `packet-encoding` |
| `trojan` | `sni`, `alpn` |
| `hysteria` | `auth-str`, `obfs`, `up` / `down`, `ports`, receive windows (protocol `udp` only) |
| `hysteria2` | `password`, `ports` + `hop-interval`, `obfs: salamander`, `up` / `down` |
| `tuic` | v5 `uuid` + `password`, `congestion-controller`, `udp-relay-mode`, `reduce-rtt`, `heartbeat-interval` |
| `wireguard` | `ip`, `ipv6`, keys, `reserved`, `mtu`, `peers` |
| `socks5`, `http` | credentials; `tls` for `http` |
| `anytls` | `password`, idle session options |
| `ssh` | `username`, `password`, `private-key`, `host-key` |

Common options: `network` `ws` (`ws-opts`, early data, `v2ray-http-upgrade`),
`grpc`, `h2`, `http` (HTTP obfuscation); `skip-cert-verify`, `alpn`,
`client-fingerprint` (uTLS), `smux`, `tfo`. Proxies sing-box cannot express
are skipped: `ssr`, `snell`, `mieru`, TUIC v4, XHTTP and mKCP transports,
`shadow-tls` / `restls` plugins, VLESS encryption, AmneziaWG and
`dialer-proxy` chains.

## sing-box-lx core

Instead of the official core an app can link
[sing-box-lx](https://github.com/Leadaxe/sing-box-lx), a fork of the same
sing-box version with client extras for current Xray and AmneziaWG servers:
the XHTTP transport, AmneziaWG 2.0 / 3.x, MASQUE (Cloudflare WARP),
TrustTunnel, the post-quantum VLESS `encryption` and REALITY key share,
`chain` outbounds, round-robin balancing, DNS server groups and idle-suspend
of WireGuard endpoints. The core is chosen when the app is built, in the
app's `pubspec.yaml`:

```yaml
sing_box:
  core: lx   # standard (default) or lx
```

The environment variable `SING_BOX_CORE` (or the Gradle property
`singBox.core`) overrides it. iOS with Swift Package Manager (the default
since Flutter 3.44) cannot read the app's `pubspec.yaml`: build with
`SING_BOX_CORE=lx flutter build ios` (or start Xcode from a shell with that
variable); CocoaPods builds read the `pubspec.yaml`. After switching the core
on iOS run `flutter clean` and delete `~/Library/Developer/Xcode/DerivedData/
Runner-*`, otherwise Xcode keeps the other core's precompiled module. At runtime `SingBox.instance.core` tells which
core runs and `supports(SingBoxCoreFeature.xhttp)` checks a feature; members
that need the lx core live in `SingBoxExtended.instance` (the same object as
`SingBox.instance`) and throw a `SingBoxUnsupportedException` ("requires the
sing-box-lx core") on the standard core.

Status: the lx libbox is not published yet, build it with
`scripts/build_libbox.sh android apple --core lx --install`. The plugin's
whole Android end-to-end suite passes on both cores; on iOS the simulator
checks (no tunnel there) pass with both cores, with SwiftPM and CocoaPods. A
running lx tunnel on an iPhone is not tested yet: the Network Extension has
a ~50 MB memory limit and the lx core is ~5 % larger.

## Building libbox yourself

```bash
scripts/build_libbox.sh android apple --install
```

The script fetches the sing-box version from `LIBBOX_VERSION`, installs
SagerNet's `gomobile` and builds `build/libbox/libbox.aar` and
`build/libbox/Libbox.xcframework(.zip)` with SHA-256 files. `--install` copies
them into the plugin so local builds skip the download. Requirements: Go 1.25+,
Android SDK + NDK, JDK 17/21, Xcode. Set `LIBBOX_TAGS` to change the compiled
features. `--core lx` builds the sing-box-lx core (version from
`LIBBOX_LX_VERSION`) into `build/libbox-lx/`; `--install` then puts it at
`android/libs/libbox-lx.aar` and `ios/sing_box/Frameworks/lx/`.

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
  avoid huge rule-sets and keep `oomKiller` at `platformDefault` or `enabled`.
- **The first build is slow** - the native library is downloaded once and
  cached.

## Publishing an app that uses sing_box

- **GPL**: the plugin and the sing-box core are GPL-3.0-or-later, so an app
  that ships them is distributed under the GPL as well: publish the app's
  complete corresponding source code under a GPL-compatible license and keep
  the notices (see [License](#license)).
- **Google Play**: apps that use `VpnService` must have VPN as their core
  functionality and fill in the VPN declaration and the foreground service
  declaration (`systemExempted`) in the Play Console. Apps that declare
  `SingBoxProxyService` for the proxy-only mode also describe the
  `specialUse` foreground service there.
- **App Store**: VPN apps must be published by a developer enrolled as an
  organization (App Review Guideline 5.4) and need the Network Extension
  entitlement for both the app and the extension.
- **Size**: ship an App Bundle (Android) - each ABI adds ~60 MB of libbox.

## Migrating from 0.0.1

1.0.0 is a rewrite on top of sing-box 1.14:

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

## Contributing

Bug reports and pull requests are welcome. [CONTRIBUTING.md](CONTRIBUTING.md)
describes the development setup, the test suites (unit tests validated with
the real sing-box CLI, Android emulator end-to-end tests, the iOS simulator
smoke test) and [how releases are made](doc/releasing.md).

## License

Copyright (C) 2025-2026 QUSAD-prod.

This program is free software: you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free Software
Foundation, either version 3 of the License, or (at your option) any later
version ([LICENSE](LICENSE)). Versions up to 0.0.1 were released under the MIT
License.

The native code is partly adapted from the official sing-box clients, and the
sing-box core (`libbox`) is GPL-3.0-or-later with an additional naming clause;
see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). "sing-box" is the name of
the SagerNet project; this plugin is not affiliated with it.
