# sing_box example

A complete VPN client built with the [`sing_box`](https://pub.dev/packages/sing_box)
plugin. It exercises most of the API:

| Page | What it demonstrates |
| --- | --- |
| **sing-box VPN** | connect / disconnect, live status with error reasons, traffic speed and totals, latency of the current server, network quality speed test |
| **Servers** | importing share links and subscriptions, server profiles, connecting to all servers at once, groups with URL test and instant switching |
| **Routing** | bypass / blocked / proxy-only apps, domains and subnets, bypass LAN and countries, ad blocking, custom DNS |
| **Logs** | the live core log buffer |
| **Tools** | permissions, settings (auto connect, kill switch, start on boot), Always-on VPN settings, Quick Settings tile, clash mode, active connections, STUN NAT test, the running config |

The essentials fit in a few lines:

```dart
import 'package:sing_box/sing_box.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SingBox.instance.initialize(const SingBoxOptions(
    android: SingBoxAndroidOptions(notificationTitle: 'sing_box example'),
    ios: SingBoxIosOptions(profileName: 'sing_box example'),
  ));
  runApp(const ExampleApp());
}

// Somewhere in the UI:
await SingBox.instance.connect('vless://…');
SingBox.instance.watchConnectionState().listen((state) => print(state));
```

## Running it

```bash
cd example
flutter run
```

The first build downloads the sing-box core (libbox) from the plugin's GitHub
releases and caches it.

- **Android**: works on devices and emulators (API 24+). Paste a share link on
  the *Servers* page and connect.
- **iOS**: the project already contains the Packet Tunnel extension
  (`ios/PacketTunnel`, bundle ids `com.qusadprod.singBoxExample` and
  `com.qusadprod.singBoxExample.PacketTunnel`, App Group
  `group.com.qusadprod.singBoxExample`). Set your own team and bundle ids in
  Xcode before running on a device; the tunnel needs a paid Apple Developer
  account and does not run in the Simulator (the UI does).

## Tests

| Command | What it checks |
| --- | --- |
| `flutter test integration_test/smoke_test.dart -d <device>` | Platform smoke test without a VPN server (also on the iOS Simulator) |
| `flutter test integration_test/vpn_e2e_test.dart -d emulator-5554` | End-to-end VPN tests against local sing-box servers (`integration_test/server/`) |
| `flutter test integration_test/permission_e2e_test.dart -d emulator-5554` | Behaviour without the VPN permission |

`lib/e2e_harness.dart` is a minimal entry point for manual Android lifecycle
checks (closing the app, Quick Settings tile, boot start, Always-on VPN); see
the plugin's [Android guide](../doc/android.md#checking-the-lifecycle-on-a-device)
and [CONTRIBUTING.md](../CONTRIBUTING.md).
