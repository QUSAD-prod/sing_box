# iOS guide

This page complements the [README](../README.md#ios-setup) with the details
of the iOS implementation.

## How it works

* A VPN on iOS runs in a **Packet Tunnel Network Extension**, a separate
  process with a memory limit of about 50 MB. The sing-box core (libbox
  1.14.4) runs there in `SingBoxPacketTunnelProvider`, shipped by the plugin
  as the `SingBoxTunnel` library: your extension only subclasses it, so
  updating the plugin updates the tunnel code too.
* The app side (the Flutter plugin) manages a `NETunnelProviderManager`
  profile, writes the configuration to
  `<App Group container>/sing-box/config.json` and talks to the core through
  the libbox command server in the App Group container.
* Reloads (`reload()`, `switchServer()`, rule changes) are sent to the
  extension with `sendProviderMessage`; the extension re-reads the file and
  reloads the core without tearing down the tunnel.
* When the core stops or fails, the extension cancels the tunnel with the
  error, which the app reports in `SingBoxConnectionState.error` (and in the
  `SingBoxStartException` thrown by `connect()`).
* Sleep/wake and network changes are forwarded to the core (pause/wake,
  `NWPathMonitor` for the default interface).

## Requirements

| | |
| --- | --- |
| iOS | 15.0+ |
| Xcode | 16+ |
| Apple Developer account | paid (free personal teams cannot use Network Extensions) |
| Device | VPN tunnels do not run in the iOS Simulator; everything else does |

## Scripted setup

```bash
flutter build ios --config-only     # lets Flutter generate its Swift package / Podfile
dart run sing_box:setup_ios \
  [--bundle-id com.example.app.PacketTunnel] [--app-group group.com.example.app] [--team ABCDE12345]
```

Pure Dart, no Ruby gems. It edits `Runner.xcodeproj` the way Xcode would
and is idempotent; re-run it after changing the ids. The `SingBoxTunnel`
library is linked to the extension

* with **Swift Package Manager** (Flutter's generated package depends on
  sing_box): as a product of `FlutterGeneratedPluginSwiftPackage`, which
  Xcode resolves through the package graph. The reference does not contain
  the plugin's version or path, so it survives plugin upgrades. No Podfile,
  no CocoaPods;
* with **CocoaPods**: `pod 'SingBoxTunnel'` (static) for the extension in
  `ios/Podfile`. A project that already has this pod keeps it (linking the
  library twice would duplicate symbols); to switch such a project to Swift
  Package Manager remove the extension's block from the Podfile and run the
  tool again.

Before the first `flutter build` neither exists and the tool asks to build
once and run it again. `ios/scripts/add_packet_tunnel.rb` from 1.0.0 is now
a wrapper around this command.

## Manual setup

1. **App Group**: create one (e.g. `group.com.example.myapp`) and enable
   *App Groups* and *Network Extensions → Packet Tunnel* for the Runner.
2. **Extension target**: *File → New → Target… → Network Extension*, name
   `PacketTunnel`, provider type *Packet Tunnel*, Swift. Bundle id
   `<app bundle id>.PacketTunnel`, deployment target 15.0, the same two
   capabilities and App Group.
3. **Provider**: replace the generated `PacketTunnelProvider.swift` with
   ```swift
   import SingBoxTunnel

   class PacketTunnelProvider: SingBoxPacketTunnelProvider {}
   ```
4. **Info.plist** of the extension: add `SingBoxAppGroup` = your App Group
   (used when iOS starts the tunnel without the app, e.g. On Demand).
5. **Link the library** to the extension.
   * Swift Package Manager: in the extension target's *Frameworks and
     Libraries* add the `SingBoxTunnel` product. Xcode lists only products of
     packages referenced by the project, so add it in
     `project.pbxproj` as an `XCSwiftPackageProductDependency` with
     `productName = SingBoxTunnel` whose `package` is the existing
     `FlutterGeneratedPluginSwiftPackage` reference (the setup tool does
     this). Do not add a second package reference to
     `ios/Flutter/ephemeral/Packages/.packages/<plugin folder>`: that folder
     name contains the plugin version from the pub cache and changes on
     every upgrade.
   * CocoaPods: add to `ios/Podfile` and run `pod install`:
     ```ruby
     target 'PacketTunnel' do
       use_frameworks! :linkage => :static
       pod 'SingBoxTunnel', :path => '.symlinks/plugins/sing_box/ios'
     end
     ```
6. **Build phases** of Runner: *Embed Foundation Extensions* must come
   before Flutter's *Thin Binary* script, otherwise Xcode reports
   *"Cycle inside Runner; building could produce unreliable results"*.
7. **Versions**: keep `CFBundleShortVersionString`/`CFBundleVersion` of the
   extension equal to the app's (App Store requirement); the setup tool uses
   `$(FLUTTER_BUILD_NAME)`/`$(FLUTTER_BUILD_NUMBER)` from
   `Flutter/Generated.xcconfig`.

If you use other ids than `group.<bundle id>` and `<bundle id>.PacketTunnel`,
pass them to `initialize`:

```dart
await SingBox.instance.initialize(const SingBoxOptions(
  ios: SingBoxIosOptions(
    appGroup: 'group.com.example.shared',
    tunnelBundleIdentifier: 'com.example.myapp.VPN',
    profileName: 'My VPN',        // shown in Settings → VPN
  ),
));
```

## Service options

| Setting | iOS behaviour |
| --- | --- |
| `autoReconnectOnDisconnect` / `setServiceOptions(onDemand: true)` | VPN On Demand with a connect rule for every interface: iOS reconnects automatically, also after a reboot. `disconnect()` turns it off so the tunnel stays down |
| `killSwitch` / `includeAllNetworks` | `protocolConfiguration.includeAllNetworks` (iOS 14+): all traffic must use the tunnel. Off by default - it also captures traffic that usually bypasses VPNs and breaks AirDrop/CarPlay while connected |
| `excludeLocalNetworks` | Local network traffic bypasses the tunnel (default on, so LAN printers and casting keep working with the kill switch) |
| `excludeAPNs` | Push notifications bypass the tunnel (iOS 16.4+, default on) |
| `enforceRoutes` | Without the kill switch: iOS scopes the tunnel's routes to the VPN even for apps that bind to an interface |
| `excludeCellularServices` | Wi-Fi Calling, MMS, SMS and Visual Voicemail bypass the tunnel with the kill switch (iOS 16.4+) |
| `excludeDeviceCommunication` | Communication with paired devices bypasses the tunnel with the kill switch (iOS 17.4+) |
| `excludeDefaultRoute` | Hides the VPN icon (`0.0.0.0/31`, `::/127` excluded), as "Hide VPN Icon" in sing-box-for-apple |
| `noDefaultRoute` | Routes the address space in ranges instead of a default route (sing-box-for-apple's "No Default Route", helps HomeKit) |
| `excludeApnsRoute` | Push notifications bypass the tunnel on every iOS version (`17.0.0.0/8` excluded, `push.apple.com` bypasses the system proxy) |

The last three are applied by the extension when the tunnel starts or
reloads. Native crash reports (PLCrashReporter in sing-box-for-apple) are not
included; Go crashes and memory pressure are reported, see
`SingBox.getCoreReports()`.

Nothing is forced: flutter_vless enabled the kill switch unconditionally,
which broke local networking for many users.

## Memory

The extension is limited to about 50 MB. libbox for iOS is built with
`with_low_memory` and the libbox OOM killer is enabled in the extension
(`SingBoxSettings.oomKiller`: `platformDefault` = `enabled`; `reportOnly`
only records out-of-memory reports, `off` disables it - only for debugging).
Under a Network Extension the monitor always uses the system limit (50 MB);
`SingBoxSettings.memoryLimitMb` only moves the Go garbage collector target
(80 % of it).
Keep configurations lean: large remote rule-sets, many outbounds or big
connection counts raise the memory use.

## Latency tests

* Connected: the app's request to the probe address (`198.51.100.1`,
  `SingBoxConfigOptions.probeAddress`) enters the tunnel and is routed
  through the measured outbound. The TUN's neighbour address (`172.19.0.2`)
  cannot be used: sing-box treats every TCP connection to it as DNS.
* Stopped: the proxy methods start a temporary libbox service in the app
  process (no TUN, never started command server, inbounds on `127.0.0.1`).
* `tcp` / `icmp`: measured in the app while the tunnel is down; while it is
  up the plugin sends them to the extension (`sendProviderMessage`), which
  resolves the name with `DNSServiceGetAddrInfo` on the physical interface
  and binds the sockets to it (`IP_BOUND_IF`), so neither the tunnel nor its
  DNS (FakeIP) is involved. ICMP uses unprivileged `SOCK_DGRAM` sockets.
  The simulator has no tunnel: only the disconnected paths can be tested
  there.

## Speed and NAT tests

`runNetworkQualityTest()` / `testSpeed()` and `runStunTest()` run through the
tunnel while it is connected and test the direct connection from the app
otherwise.

## Building libbox offline

`Libbox.xcframework` (~200 MB unpacked) is not part of the pub package.

* **Swift Package Manager** downloads `Libbox.xcframework.zip` from the
  GitHub release `libbox-v<version>` and verifies the checksum in
  `ios/sing_box/Package.swift`.
* **CocoaPods** (`ios/libbox.rb`) uses, in this order: a local
  `ios/sing_box/Frameworks/Libbox.xcframework`; the zip given by
  `SING_BOX_LIBBOX_XCFRAMEWORK_ZIP`; a download into
  `~/Library/Caches/sing_box/libbox/<version>/` (mirror:
  `SING_BOX_LIBBOX_BASE_URL`), verified with SHA-256.

To build it yourself: `scripts/build_libbox.sh apple --install` (needs Go and
`gomobile`); the script also converts the gomobile output into the shallow
framework bundles iOS requires.

## Troubleshooting

| Symptom | Cause / fix |
| --- | --- |
| `requestVpnPermission()` returns `false` / `PERMISSION_DENIED` | The user declined the *Add VPN Configurations* alert, or the profile cannot be saved: check the Network Extension capability, the extension bundle id and the App Group of both targets (same team) |
| `SingBoxStartException` right after `connect()` | The core failed in the extension; the message is the sing-box error (unreachable rule-set, broken outbound, …) |
| `Cycle inside Runner` | Move *Embed Foundation Extensions* above *Thin Binary* |
| `Missing package product 'SingBoxTunnel'` | Do not link the Swift package product; use the `SingBoxTunnel` pod (see above) |
| The extension is killed under load | The 50 MB limit: reduce rule-sets/outbounds, keep the OOM killer on |
| Works in debug, not from TestFlight | Both targets need the capabilities in the distribution provisioning profiles |
| Nothing happens in the Simulator | Network Extensions only run on devices |
