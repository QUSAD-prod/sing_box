# sing_box

A Flutter plugin for sing-box, providing platform-specific implementations for Android and iOS.

> **⚠️ Warning**: This is an unstable project currently under testing. The API may change, and there may be bugs. Any help, feedback, and contributions are welcome!

## Features

- ✅ Platform-specific implementations for Android and iOS
- ✅ VPN connection management (connect/disconnect)
- ✅ Connection status monitoring (real-time Stream)
- ✅ Connection statistics (speed, bytes sent/received, ping, connection duration)
- ✅ Speed testing
- ✅ Ping measurement (current server)
- ✅ App and domain bypass management
- ✅ Subnet bypass management (CIDR notation)
- ✅ DNS servers management
- ✅ Server switching
- ✅ Settings persistence (auto-connect, auto-reconnect, kill switch)
- ✅ Multiple server configurations with different protocols
- ✅ Blocked apps and domains management
- ✅ Observer pattern for logging (with Talker integration support)
- ✅ Notifications from sing-box

## Requirements

### Minimum Versions

- **Android**: API 23+ (Android 6.0+)
- **iOS**: iOS 15.0+
- **Flutter**: 3.3.0 or higher

### Development Tools

- **Flutter SDK**: Install Flutter SDK (version 3.3.0 or higher)
- **Android Studio / Xcode**: For Android/iOS development
- **Physical Device or Emulator**: VPN functionality requires a real device or emulator

## Installation

### Add Dependency

Add this to your package's `pubspec.yaml` file:

```yaml
dependencies:
  sing_box: ^0.0.1
```

Then run:

```bash
flutter pub get
```

### Platform Setup

#### Android

1. **Minimum SDK**: Android API 23 (Android 6.0) or higher

2. **Permissions**: The plugin automatically declares required permissions in `AndroidManifest.xml`:
   - `INTERNET`
   - `BIND_VPN_SERVICE`
   - `FOREGROUND_SERVICE`
   - `POST_NOTIFICATIONS`
   - `ACCESS_NETWORK_STATE`
   - `ACCESS_WIFI_STATE`

3. **VPN Permission**: The plugin will request VPN permission when you call `connect()`. The user must grant this permission for VPN to work.

#### iOS

1. **Minimum iOS Version**: iOS 15.0 or higher

2. **Network Extension**: The plugin uses Network Extension for VPN functionality. You need to:
   - Enable Network Extension capability in Xcode
   - Configure App Groups for communication between main app and extension
   - The extension is automatically configured during build

3. **Permissions**: The plugin automatically handles required permissions.

## Quick Start

### 1. Initialize Plugin

The plugin uses Singleton pattern and must be initialized before using other methods, preferably before application start:

```dart
import 'package:flutter/widgets.dart';
import 'package:sing_box/sing_box.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize plugin
  await SingBox.instance.initialize();
  
  runApp(MyApp());
}
```

### 2. Basic Connection

```dart
import 'package:sing_box/sing_box.dart';

final singBox = SingBox.instance;

// Connect to VPN with JSON configuration
final config = '''
{
  "outbounds": [
    {
      "type": "vmess",
      "tag": "proxy",
      "server": "example.com",
      "server_port": 443,
      "uuid": "your-uuid-here",
      "security": "auto"
    }
  ]
}
''';

final connected = await singBox.connect(config);
if (connected) {
  print('Connected successfully!');
}

// Disconnect
await singBox.disconnect();
```

### 3. Monitor Connection Status

```dart
// Listen to connection status changes
singBox.watchSingBoxConnectionStatus().listen((status) {
  print('Status: ${status.name}');
  // Status values: disconnected, connecting, connected, disconnecting, 
  // disconnectedByUser, connectionLost, error
});
```

### 4. Monitor Statistics

```dart
// Listen to connection statistics in real-time
singBox.watchSingBoxConnectionStats().listen((stats) {
  print('Download: ${stats.downloadSpeed} B/s');
  print('Upload: ${stats.uploadSpeed} B/s');
  print('Ping: ${stats.ping} ms');
  print('Duration: ${stats.connectionDuration} ms');
});
```

## API Documentation

### Initialization

#### `initialize()`

Initialize the plugin. Must be called before using other methods.

```dart
Future<bool> initialize()
```

**Returns**: `true` if initialization successful, `false` otherwise.

**Example**:
```dart
final success = await SingBox.instance.initialize();
```

---

### Platform Information

#### `getPlatformVersion()`

Get the platform version string.

```dart
Future<String?> getPlatformVersion()
```

**Returns**: Platform version string (e.g., "Android 12" or "iOS 15.0").

**Example**:
```dart
final version = await singBox.getPlatformVersion();
print('Platform: $version');
```

---

### VPN Connection

#### `connect(String config)`

Connect to VPN with specified configuration.

```dart
Future<bool> connect(String config)
```

**Parameters**:
- `config` (String): JSON string with server configuration (sing-box format)

**Returns**: `true` if connection started successfully, `false` otherwise.

**Example**:
```dart
final config = '{"outbounds": [{"type": "vmess", ...}]}';
final connected = await singBox.connect(config);
```

**Note**: On Android, this will request VPN permission if not already granted.

#### `disconnect()`

Disconnect from VPN.

```dart
Future<bool> disconnect()
```

**Returns**: `true` if disconnection started successfully, `false` otherwise.

**Example**:
```dart
await singBox.disconnect();
```

#### `getConnectionStatus()`

Get current connection status.

```dart
Future<SingBoxConnectionStatus> getConnectionStatus()
```

**Returns**: Current connection status enum.

**Status Values**:
- `disconnected` - Not connected
- `connecting` - Connecting in progress
- `connected` - Connected
- `disconnecting` - Disconnecting in progress
- `disconnectedByUser` - Disconnected by user
- `connectionLost` - Connection lost with server
- `error` - Connection error

**Example**:
```dart
final status = await singBox.getConnectionStatus();
if (status == SingBoxConnectionStatus.connected) {
  print('VPN is connected');
}
```

#### `watchSingBoxConnectionStatus()`

Subscribe to connection status changes. Returns a Stream that emits status updates.

```dart
Stream<SingBoxConnectionStatus> watchSingBoxConnectionStatus()
```

**Returns**: Stream of connection status updates.

**Example**:
```dart
singBox.watchSingBoxConnectionStatus().listen((status) {
  switch (status) {
    case SingBoxConnectionStatus.connected:
      print('Connected!');
      break;
    case SingBoxConnectionStatus.disconnected:
      print('Disconnected');
      break;
    // ... other cases
  }
});
```

---

### Connection Statistics

#### `getConnectionStats()`

Get current connection statistics.

```dart
Future<SingBoxConnectionStats> getConnectionStats()
```

**Returns**: `SingBoxConnectionStats` object with:
- `downloadSpeed` (int): Current download speed in bytes per second
- `uploadSpeed` (int): Current upload speed in bytes per second
- `bytesSent` (int): Total bytes sent
- `bytesReceived` (int): Total bytes received
- `ping` (int?): Current ping in milliseconds (nullable)
- `connectionDuration` (int): Connection duration in milliseconds

**Example**:
```dart
final stats = await singBox.getConnectionStats();
print('Download: ${stats.downloadSpeed} B/s');
print('Upload: ${stats.uploadSpeed} B/s');
print('Ping: ${stats.ping} ms');
```

#### `watchSingBoxConnectionStats()`

Subscribe to connection statistics changes. Returns a Stream that emits statistics updates every second.

```dart
Stream<SingBoxConnectionStats> watchSingBoxConnectionStats()
```

**Returns**: Stream of connection statistics updates.

**Example**:
```dart
singBox.watchSingBoxConnectionStats().listen((stats) {
  // Update UI with real-time statistics
  setState(() {
    downloadSpeed = stats.downloadSpeed;
    uploadSpeed = stats.uploadSpeed;
    ping = stats.ping;
  });
});
```

---

### Speed Testing

#### `testSpeed()`

Measure connection speed.

```dart
Future<SingBoxSpeedTestResult> testSpeed()
```

**Returns**: `SingBoxSpeedTestResult` with:
- `downloadSpeed` (int): Download speed in bytes per second
- `uploadSpeed` (int): Upload speed in bytes per second
- `success` (bool): Whether test was successful
- `errorMessage` (String?): Error message if test failed

**Example**:
```dart
final result = await singBox.testSpeed();
if (result.success) {
  print('Download: ${result.downloadSpeed} B/s');
  print('Upload: ${result.uploadSpeed} B/s');
} else {
  print('Error: ${result.errorMessage}');
}
```

---

### Ping

#### `pingCurrentServer()`

Measure ping to current server.

```dart
Future<SingBoxPingResult> pingCurrentServer()
```

**Returns**: `SingBoxPingResult` with:
- `ping` (int): Ping in milliseconds
- `success` (bool): Whether ping was successful
- `errorMessage` (String?): Error message if ping failed
- `address` (String?): Server address

**Example**:
```dart
final result = await singBox.pingCurrentServer();
if (result.success) {
  print('Ping: ${result.ping} ms to ${result.address}');
} else {
  print('Error: ${result.errorMessage}');
}
```

---

### Bypass Management

#### `addAppToBypass(String packageName)`

Add app to bypass list (app will not use VPN).

```dart
Future<bool> addAppToBypass(String packageName)
```

**Parameters**:
- `packageName` (String): App package name (Android) or bundle ID (iOS)

**Returns**: `true` if added successfully, `false` otherwise.

**Example**:
```dart
await singBox.addAppToBypass('com.example.app');
```

#### `removeAppFromBypass(String packageName)`

Remove app from bypass list.

```dart
Future<bool> removeAppFromBypass(String packageName)
```

**Example**:
```dart
await singBox.removeAppFromBypass('com.example.app');
```

#### `getBypassApps()`

Get list of apps in bypass.

```dart
Future<List<String>> getBypassApps()
```

**Returns**: List of package names/bundle IDs.

**Example**:
```dart
final apps = await singBox.getBypassApps();
print('Bypass apps: $apps');
```

#### `addDomainToBypass(String domain)`

Add domain/site to bypass list (domain will not use VPN).

```dart
Future<bool> addDomainToBypass(String domain)
```

**Parameters**:
- `domain` (String): Domain name or IP address

**Example**:
```dart
await singBox.addDomainToBypass('example.com');
```

#### `removeDomainFromBypass(String domain)`

Remove domain from bypass list.

```dart
Future<bool> removeDomainFromBypass(String domain)
```

#### `getBypassDomains()`

Get list of domains in bypass.

```dart
Future<List<String>> getBypassDomains()
```

**Example**:
```dart
final domains = await singBox.getBypassDomains();
```

#### `addSubnetToBypass(String subnet)`

Add subnet to bypass list (subnet will not use VPN).

```dart
Future<bool> addSubnetToBypass(String subnet)
```

**Parameters**:
- `subnet` (String): Subnet in CIDR notation (e.g., "192.168.1.0/24", "10.0.0.0/8")

**Example**:
```dart
await singBox.addSubnetToBypass('192.168.1.0/24');
await singBox.addSubnetToBypass('10.0.0.0/8');
```

#### `removeSubnetFromBypass(String subnet)`

Remove subnet from bypass list.

```dart
Future<bool> removeSubnetFromBypass(String subnet)
```

#### `getBypassSubnets()`

Get list of subnets in bypass.

```dart
Future<List<String>> getBypassSubnets()
```

**Example**:
```dart
final subnets = await singBox.getBypassSubnets();
```

---

### DNS Servers Management

#### `addDnsServer(String dnsServer)`

Add DNS server.

```dart
Future<bool> addDnsServer(String dnsServer)
```

**Parameters**:
- `dnsServer` (String): DNS server IP address (e.g., "8.8.8.8", "1.1.1.1")

**Example**:
```dart
await singBox.addDnsServer('8.8.8.8'); // Google DNS
await singBox.addDnsServer('1.1.1.1'); // Cloudflare DNS
```

#### `removeDnsServer(String dnsServer)`

Remove DNS server.

```dart
Future<bool> removeDnsServer(String dnsServer)
```

#### `getDnsServers()`

Get list of DNS servers.

```dart
Future<List<String>> getDnsServers()
```

**Example**:
```dart
final dnsServers = await singBox.getDnsServers();
```

#### `setDnsServers(List<String> dnsServers)`

Set DNS servers (replaces all existing DNS servers).

```dart
Future<bool> setDnsServers(List<String> dnsServers)
```

**Parameters**:
- `dnsServers` (List<String>): List of DNS server IP addresses

**Example**:
```dart
await singBox.setDnsServers(['8.8.8.8', '8.8.4.4']);
```

---

### Server Switching

#### `switchServer(String config)`

Switch current server. Stops current connection, changes configuration and connects to new server.

```dart
Future<bool> switchServer(String config)
```

**Parameters**:
- `config` (String): JSON string with new server configuration

**Example**:
```dart
final newConfig = '{"outbounds": [{"type": "vless", ...}]}';
final switched = await singBox.switchServer(newConfig);
```

---

### Settings Management

#### `saveSettings(SingBoxSettings settings)`

Save settings.

```dart
Future<bool> saveSettings(SingBoxSettings settings)
```

**Parameters**:
- `settings` (SingBoxSettings): Settings object to save

**Example**:
```dart
final settings = SingBoxSettings(
  autoConnectOnStart: true,
  autoReconnectOnDisconnect: true,
  killSwitch: true,
);
await singBox.saveSettings(settings);
```

#### `loadSettings()`

Load settings.

```dart
Future<SingBoxSettings> loadSettings()
```

**Returns**: `SingBoxSettings` object.

**Example**:
```dart
final settings = await singBox.loadSettings();
```

#### `getSettings()`

Get current settings.

```dart
Future<SingBoxSettings> getSettings()
```

**Example**:
```dart
final settings = await singBox.getSettings();
```

#### `updateSetting(String key, dynamic value)`

Update individual setting parameter.

```dart
Future<bool> updateSetting(String key, dynamic value)
```

**Parameters**:
- `key` (String): Parameter key (`autoConnectOnStart`, `autoReconnectOnDisconnect`, `killSwitch`)
- `value` (dynamic): Parameter value

**Example**:
```dart
await singBox.updateSetting('autoConnectOnStart', true);
await singBox.updateSetting('killSwitch', false);
```

**Settings Keys**:
- `autoConnectOnStart` (bool): Automatically connect on application start
- `autoReconnectOnDisconnect` (bool): Automatically reconnect on connection loss
- `killSwitch` (bool): Block all internet when VPN is disconnected

---

### Server Configurations Management

#### `addServerConfig(SingBoxServerConfig config)`

Add server configuration.

```dart
Future<bool> addServerConfig(SingBoxServerConfig config)
```

**Parameters**:
- `config` (SingBoxServerConfig): Server configuration object

**Example**:
```dart
final config = SingBoxServerConfig(
  id: 'server1-vmess',
  name: 'Server 1 - VMESS',
  config: '{"outbounds": [{"type": "vmess", ...}]}',
  protocol: 'vmess',
  server: 'server1.com',
  port: 443,
);
await singBox.addServerConfig(config);
```

#### `removeServerConfig(String configId)`

Remove server configuration.

```dart
Future<bool> removeServerConfig(String configId)
```

**Parameters**:
- `configId` (String): Configuration identifier

**Example**:
```dart
await singBox.removeServerConfig('server1-vmess');
```

#### `updateServerConfig(SingBoxServerConfig config)`

Update server configuration.

```dart
Future<bool> updateServerConfig(SingBoxServerConfig config)
```

**Example**:
```dart
final updatedConfig = config.copyWith(name: 'Updated Name');
await singBox.updateServerConfig(updatedConfig);
```

#### `getServerConfigs()`

Get all server configurations.

```dart
Future<List<SingBoxServerConfig>> getServerConfigs()
```

**Returns**: List of server configurations.

**Example**:
```dart
final configs = await singBox.getServerConfigs();
for (final config in configs) {
  print('${config.name} (${config.protocol})');
}
```

#### `getServerConfig(String configId)`

Get server configuration by ID.

```dart
Future<SingBoxServerConfig?> getServerConfig(String configId)
```

**Returns**: Server configuration or `null` if not found.

**Example**:
```dart
final config = await singBox.getServerConfig('server1-vmess');
if (config != null) {
  print('Found: ${config.name}');
}
```

#### `setActiveServerConfig(String configId)`

Set active server configuration.

```dart
Future<bool> setActiveServerConfig(String configId)
```

**Parameters**:
- `configId` (String): Configuration identifier (can be `null` to reset)

**Example**:
```dart
await singBox.setActiveServerConfig('server1-vmess');
```

#### `getActiveSingBoxServerConfig()`

Get active server configuration.

```dart
Future<SingBoxServerConfig?> getActiveSingBoxServerConfig()
```

**Returns**: Active server configuration or `null` if none is set.

**Example**:
```dart
final activeConfig = await singBox.getActiveSingBoxServerConfig();
if (activeConfig != null) {
  print('Active: ${activeConfig.name}');
}
```

---

### Blocked Apps and Domains

#### `addBlockedApp(String packageName)`

Add app to blocked list (app will not use VPN).

```dart
Future<bool> addBlockedApp(String packageName)
```

**Parameters**:
- `packageName` (String): App package name (Android) or bundle ID (iOS)

**Example**:
```dart
await singBox.addBlockedApp('com.banking.app');
```

#### `removeBlockedApp(String packageName)`

Remove app from blocked list.

```dart
Future<bool> removeBlockedApp(String packageName)
```

#### `getBlockedApps()`

Get list of blocked apps.

```dart
Future<List<String>> getBlockedApps()
```

**Example**:
```dart
final blockedApps = await singBox.getBlockedApps();
```

#### `addBlockedDomain(String domain)`

Add domain/site to blocked list (domain will not use VPN).

```dart
Future<bool> addBlockedDomain(String domain)
```

**Parameters**:
- `domain` (String): Domain name or IP address

**Example**:
```dart
await singBox.addBlockedDomain('malicious-site.com');
```

#### `removeBlockedDomain(String domain)`

Remove domain from blocked list.

```dart
Future<bool> removeBlockedDomain(String domain)
```

#### `getBlockedDomains()`

Get list of blocked domains.

```dart
Future<List<String>> getBlockedDomains()
```

**Example**:
```dart
final blockedDomains = await singBox.getBlockedDomains();
```

---

### Notifications

#### `watchNotifications()`

Subscribe to notifications from sing-box. Returns a Stream that emits notification updates.

```dart
Stream<SingBoxNotification> watchNotifications()
```

**Returns**: Stream of notification updates.

**Notification Properties**:
- `identifier` (String): Notification identifier
- `typeName` (String): Notification type name
- `typeId` (int): Notification type ID
- `title` (String): Notification title
- `subtitle` (String): Notification subtitle
- `body` (String): Notification body
- `openUrl` (String?): URL to open when notification is tapped

**Example**:
```dart
singBox.watchNotifications().listen((notification) {
  print('Notification: ${notification.title}');
  print('Body: ${notification.body}');
  if (notification.openUrl != null) {
    // Open URL
  }
});
```

---

### Observer Pattern

#### `setObserver(SingBoxObserver observer)`

Set observer for logging events.

```dart
void setObserver(SingBoxObserver observer)
```

**Example with Talker**:
```dart
import 'package:talker/talker.dart';
import 'package:sing_box/sing_box.dart';
import 'package:sing_box/src/observer/talker_observer.dart';

final talker = Talker();
final observer = SingBoxTalkerObserver(talker);
SingBox.instance.setObserver(observer);
```

**Custom Observer**:
```dart
import 'package:sing_box/sing_box.dart';
import 'package:sing_box/src/observer/sing_box_observer.dart';

class MyObserver implements SingBoxObserver {
  @override
  void info(String message, [Map<String, dynamic>? data]) {
    print('INFO: $message');
  }
  
  @override
  void warning(String message, [Map<String, dynamic>? data]) {
    print('WARNING: $message');
  }
  
  @override
  void error(String message, [Object? error, StackTrace? stackTrace]) {
    print('ERROR: $message');
  }
  
  @override
  void debug(String message, [Map<String, dynamic>? data]) {
    print('DEBUG: $message');
  }
  
  // Implement remaining methods...
}

SingBox.instance.setObserver(MyObserver());
```

---

## Complete Example

```dart
import 'package:flutter/material.dart';
import 'package:sing_box/sing_box.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize plugin
  await SingBox.instance.initialize();
  
  runApp(MyApp());
}

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final singBox = SingBox.instance;
  SingBoxConnectionStatus _status = SingBoxConnectionStatus.disconnected;
  SingBoxConnectionStats? _stats;

  @override
  void initState() {
    super.initState();
    
    // Listen to status changes
    singBox.watchSingBoxConnectionStatus().listen((status) {
      setState(() {
        _status = status;
      });
    });
    
    // Listen to statistics
    singBox.watchSingBoxConnectionStats().listen((stats) {
      setState(() {
        _stats = stats;
      });
    });
  }

  Future<void> _connect() async {
    final config = '''
    {
      "outbounds": [
        {
          "type": "vmess",
          "tag": "proxy",
          "server": "example.com",
          "server_port": 443,
          "uuid": "your-uuid-here",
          "security": "auto"
        }
      ]
    }
    ''';
    
    await singBox.connect(config);
  }

  Future<void> _disconnect() async {
    await singBox.disconnect();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: Text('Sing-Box Example')),
        body: Column(
          children: [
            Text('Status: ${_status.name}'),
            if (_stats != null) ...[
              Text('Download: ${_stats!.downloadSpeed} B/s'),
              Text('Upload: ${_stats!.uploadSpeed} B/s'),
              Text('Ping: ${_stats!.ping} ms'),
            ],
            ElevatedButton(
              onPressed: _status == SingBoxConnectionStatus.connected 
                  ? _disconnect 
                  : _connect,
              child: Text(_status == SingBoxConnectionStatus.connected 
                  ? 'Disconnect' 
                  : 'Connect'),
            ),
          ],
        ),
      ),
    );
  }
}
```

## Running the Example

### Steps

1. **Clone the repository**:
   ```bash
   git clone https://github.com/qusadprod/sing_box.git
   cd sing_box
   ```

2. **Install dependencies**:
   ```bash
   flutter pub get
   ```

3. **Run on Android**:
   ```bash
   flutter run
   ```
   
   Or specify device:
   ```bash
   flutter devices
   flutter run -d <device-id>
   ```

4. **Run on iOS**:
   ```bash
   flutter run
   ```

   **Note**: For iOS, you may need to:
   - Open `ios/Runner.xcworkspace` in Xcode
   - Configure signing and capabilities
   - Build and run from Xcode if needed

### Building for Release

#### Android Release Build

```bash
flutter build apk --release
# or
flutter build appbundle --release
```

#### iOS Release Build

```bash
flutter build ios --release
```

Then open Xcode and archive the app.

## Troubleshooting

### Android Issues

1. **VPN Permission Not Granted**:
   - The plugin will request VPN permission automatically
   - User must grant permission in system settings if denied

2. **Service Not Starting**:
   - Check AndroidManifest.xml permissions
   - Ensure VPN permission is granted

### iOS Issues

1. **Network Extension Not Working**:
   - Ensure App Groups are configured
   - Check Network Extension capability is enabled
   - Verify signing and provisioning profiles

2. **Build Errors**:
   - Run `pod install` in `ios/` directory
   - Clean build: `flutter clean && flutter pub get`

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## Acknowledgments

This plugin uses the following open-source projects:

### sing-box

- **Repository**: [SagerNet/sing-box](https://github.com/SagerNet/sing-box)
- **License**: GPL-3.0 (see [sing-box LICENSE](https://github.com/SagerNet/sing-box/blob/master/LICENSE))
- **Usage**:
  - Android: Uses `libbox` library from `experimental/libbox` directory (compiled to `libbox.aar`)
  - iOS: Uses `Libbox.xcframework` compiled from `experimental/libbox` directory
- **Source Location**:
  - Android sources: `android/libbox/`
  - iOS sources: `ios/libbox/`

The `libbox` library provides the core VPN functionality and protocol implementations for both Android and iOS platforms.

### Other Dependencies

- **Flutter SDK**: Flutter framework and plugin system
- **Kotlin Coroutines**: For asynchronous operations on Android
- **AndroidX Core**: Android support libraries
- **Gson**: JSON serialization for Android
- **plugin_platform_interface**: Flutter plugin platform interface

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

**Note**: This plugin uses `libbox` from [SagerNet/sing-box](https://github.com/SagerNet/sing-box), which is licensed under GPL-3.0. Please refer to the [sing-box LICENSE](https://github.com/SagerNet/sing-box/blob/master/LICENSE) for details.
