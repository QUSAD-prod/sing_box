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
flutter build ios --config-only     # creates ios/.symlinks
ruby ios/.symlinks/plugins/sing_box/ios/scripts/add_packet_tunnel.rb \
  [--bundle-id com.example.app.PacketTunnel] [--app-group group.com.example.app] [--team ABCDE12345]
```

The script needs the `xcodeproj` gem, which ships with CocoaPods (Homebrew
installs are found automatically). It is idempotent; re-run it after
changing the ids. See the [README](../README.md#ios-setup) for what it
changes.

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
5. **Link the library** to the extension. Add to `ios/Podfile` and run
   `pod install`:
   ```ruby
   target 'PacketTunnel' do
     use_frameworks! :linkage => :static
     pod 'SingBoxTunnel', :path => '.symlinks/plugins/sing_box/ios'
   end
   ```
   This works whether the app links the plugin with Swift Package Manager
   (Flutter's default since 3.44) or CocoaPods. Linking the `SingBoxTunnel`
   Swift package product directly is not recommended: Flutter references the
   plugin package under a folder-dependent identity
   (`ios/Flutter/ephemeral/Packages/.packages/<plugin folder>`), and a second
   reference to the same package under another path conflicts.
6. **Build phases** of Runner: *Embed Foundation Extensions* must come
   before Flutter's *Thin Binary* script, otherwise Xcode reports
   *"Cycle inside Runner; building could produce unreliable results"*.
7. **Versions**: keep `CFBundleShortVersionString`/`CFBundleVersion` of the
   extension equal to the app's (App Store requirement); the script uses
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

Nothing is forced: flutter_vless enabled the kill switch unconditionally,
which broke local networking for many users.

## Memory

The extension is limited to about 50 MB. libbox for iOS is built with
`with_low_memory` and the libbox OOM killer is enabled in the extension
(`SingBoxSettings.disableMemoryLimit` turns it off - only for debugging).
Keep configurations lean: large remote rule-sets, many outbounds or big
connection counts raise the memory use.

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
