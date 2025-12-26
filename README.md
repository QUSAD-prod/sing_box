# sing_box

A Flutter plugin for sing-box, providing platform-specific implementations for Android and iOS.

## Features

- Platform-specific implementations for Android and iOS
- Method channel communication with native code
- Extensible platform interface architecture
- VPN connection management (connect/disconnect)
- Connection status monitoring
- Connection statistics (speed, bytes sent/received, ping, connection duration)
- Speed testing
- Ping measurement (current server and config-based)
- App and domain bypass management
- Server switching
- Settings persistence (auto-connect, auto-reconnect, kill switch)
- Multiple server configurations with different protocols
- Blocked apps and domains management
- Observer pattern for logging (with Talker integration support)

## Getting Started

### Installation

Add this to your package's `pubspec.yaml` file:

```yaml
dependencies:
  sing_box: ^0.0.1
```

Then run:

```bash
flutter pub get
```

### Usage

#### Initialization

Плагин использует паттерн Singleton и должен быть инициализирован до использования других методов, желательно до старта приложения:

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

#### Logging with Observer

The plugin supports observer for logging events. You can use Talker for logging:

```dart
import 'package:talker/talker.dart';
import 'package:sing_box/sing_box.dart';
import 'package:sing_box/src/observer/talker_observer.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Setup Talker
  final talker = Talker();
  
  // Set observer for logging
  final observer = SingBoxTalkerObserver(talker);
  SingBox.instance.setObserver(observer);
  
  // Initialize plugin
  await SingBox.instance.initialize();
  
  runApp(MyApp());
}
```

Or create your own observer:

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

// Usage
SingBox.instance.setObserver(MyObserver());
```

#### Basic Usage

After initialization, you can get the instance from anywhere in the application:

```dart
import 'package:sing_box/sing_box.dart';

// Get instance (Singleton)
final singBox = SingBox.instance;

// Check if plugin is initialized
if (singBox.isInitialized) {
  // Get platform version
  final version = await singBox.getPlatformVersion();
  print('Platform version: $version');

  // Connect to VPN
  final config = '{"server": "example.com", "port": 443}';
  final connected = await singBox.connect(config);

  // Get connection status
  final status = await singBox.getConnectionStatus();
  print('Status: $status');

  // Disconnect
  await singBox.disconnect();
}
```

#### Monitoring Connection Status

```dart
// Listen to connection status changes
singBox.watchConnectionStatus().listen((status) {
  print('Connection status changed: $status');
});
```

#### Monitoring Connection Statistics

Speed tracking is available everywhere through `SingBoxConnectionStats`:

```dart
// Method 1: Get current statistics once (includes download/upload speed)
final stats = await singBox.getConnectionStats();
print('Current download speed: ${stats.downloadSpeed} B/s');
print('Current upload speed: ${stats.uploadSpeed} B/s');

// Method 2: Listen to connection statistics in real-time (Stream)
// This provides continuous updates of download/upload speed
singBox.watchConnectionStats().listen((stats) {
  print('Download speed: ${stats.downloadSpeed} B/s');
  print('Upload speed: ${stats.uploadSpeed} B/s');
  print('Bytes sent: ${stats.bytesSent}');
  print('Bytes received: ${stats.bytesReceived}');
  print('Ping: ${stats.ping} ms');
  
  // Connection duration in milliseconds
  final durationSeconds = stats.connectionDuration ~/ 1000;
  final minutes = durationSeconds ~/ 60;
  final seconds = durationSeconds % 60;
  print('Connection time: ${minutes}m ${seconds}s');
});

// Method 3: Speed test (measures connection speed)
final speedTest = await singBox.testSpeed();
print('Test download speed: ${speedTest.downloadSpeed} B/s');
print('Test upload speed: ${speedTest.uploadSpeed} B/s');
```

**Speed tracking is available in:**
- `SingBoxConnectionStats` - real-time speed (downloadSpeed, uploadSpeed)
- `watchConnectionStats()` - Stream with continuous speed updates
- `getConnectionStats()` - current speed snapshot
- `testSpeed()` - speed test result
- Observer `onConnectionStatsChanged()` - logs speed changes

#### Speed Testing and Ping

```dart
// Test connection speed
final speedResult = await singBox.testSpeed();
print('Download: ${speedResult.downloadSpeed} B/s');
print('Upload: ${speedResult.uploadSpeed} B/s');

// Ping current server
final pingResult = await singBox.pingCurrentServer();
print('Ping: ${pingResult.ping} ms');

```

#### Bypass Management

```dart
// Add app to bypass list
await singBox.addAppToBypass('com.example.app');

// Add domain to bypass list
await singBox.addDomainToBypass('example.com');

// Get bypass lists
final apps = await singBox.getBypassApps();
final domains = await singBox.getBypassDomains();

// Remove from bypass
await singBox.removeAppFromBypass('com.example.app');
await singBox.removeDomainFromBypass('example.com');

// Add subnet to bypass list (CIDR notation)
await singBox.addSubnetToBypass('192.168.1.0/24');
await singBox.addSubnetToBypass('10.0.0.0/8');

// Get bypass subnets
final subnets = await singBox.getBypassSubnets();

// Remove subnet from bypass
await singBox.removeSubnetFromBypass('192.168.1.0/24');
```

#### DNS Servers Management

```dart
// Add DNS server
await singBox.addDnsServer('8.8.8.8'); // Google DNS
await singBox.addDnsServer('1.1.1.1'); // Cloudflare DNS

// Get DNS servers
final dnsServers = await singBox.getDnsServers();

// Set DNS servers (replaces all existing)
await singBox.setDnsServers(['8.8.8.8', '8.8.4.4']);

// Remove DNS server
await singBox.removeDnsServer('8.8.8.8');
```

#### Server Switching

```dart
// Switch to a new server
final newConfig = '{"server": "newserver.com", "port": 443}';
final switched = await singBox.switchServer(newConfig);
```

#### Settings Management

```dart
// Load settings
final settings = await singBox.loadSettings();

// Update settings
final updatedSettings = settings.copyWith(
  autoConnectOnStart: true,
  autoReconnectOnDisconnect: true,
  killSwitch: true,
  bypassSubnets: ['192.168.1.0/24', '10.0.0.0/8'],
  dnsServers: ['8.8.8.8', '1.1.1.1'],
);

// Save settings
await singBox.saveSettings(updatedSettings);

// Or update individual setting
await singBox.updateSetting('autoConnectOnStart', true);
await singBox.updateSetting('autoReconnectOnDisconnect', true);
await singBox.updateSetting('killSwitch', true);

// Get current settings
final currentSettings = await singBox.getSettings();
```

#### Server Configurations Management

```dart
// Add server configuration with different protocols
final vmessConfig = SingBoxServerConfig(
  id: 'server1-vmess',
  name: 'Server 1 - VMESS',
  config: '{"protocol": "vmess", "server": "server1.com", "port": 443}',
  protocol: 'vmess',
  server: 'server1.com',
  port: 443,
);

final vlessConfig = SingBoxServerConfig(
  id: 'server1-vless',
  name: 'Server 1 - VLESS',
  config: '{"protocol": "vless", "server": "server1.com", "port": 443}',
  protocol: 'vless',
  server: 'server1.com',
  port: 443,
);

// Add configurations
await singBox.addServerConfig(vmessConfig);
await singBox.addServerConfig(vlessConfig);

// Get all configurations
final configs = await singBox.getServerConfigs();

// Set active configuration
await singBox.setActiveServerConfig('server1-vmess');

// Get active configuration
final activeConfig = await singBox.getActiveServerConfig();

// Update configuration
final updatedConfig = vmessConfig.copyWith(name: 'Server 1 - VMESS Updated');
await singBox.updateServerConfig(updatedConfig);

// Remove configuration
await singBox.removeServerConfig('server1-vmess');
```

#### Blocked Apps and Domains

```dart
// Add app to blocked list (won't use VPN)
await singBox.addBlockedApp('com.example.app');

// Add domain to blocked list (won't use VPN)
await singBox.addBlockedDomain('example.com');

// Get blocked lists
final blockedApps = await singBox.getBlockedApps();
final blockedDomains = await singBox.getBlockedDomains();

// Remove from blocked list
await singBox.removeBlockedApp('com.example.app');
await singBox.removeBlockedDomain('example.com');
```

#### Complete Settings Example

```dart
// Initialize and configure settings
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  final singBox = SingBox.instance;
  await singBox.initialize();
  
  // Load or create settings
  var settings = await singBox.loadSettings();
  
  // Configure auto-connect and auto-reconnect
  settings = settings.copyWith(
    autoConnectOnStart: true,
    autoReconnectOnDisconnect: true,
    killSwitch: true,
  );
  
  // Add server configurations
  final server1Vmess = ServerConfig(
    id: 's1-vmess',
    name: 'Server 1 VMESS',
    config: '{"protocol": "vmess", ...}',
    protocol: 'vmess',
    server: 'server1.com',
    port: 443,
  );
  
  final server1Vless = ServerConfig(
    id: 's1-vless',
    name: 'Server 1 VLESS',
    config: '{"protocol": "vless", ...}',
    protocol: 'vless',
    server: 'server1.com',
    port: 443,
  );
  
  await singBox.addServerConfig(server1Vmess);
  await singBox.addServerConfig(server1Vless);
  
  // Set active configuration
  await singBox.setActiveServerConfig('s1-vmess');
  
  // Add blocked apps and domains
  await singBox.addBlockedApp('com.banking.app');
  await singBox.addBlockedDomain('banking.com');
  
  // Save settings
  await singBox.saveSettings(settings);
  
  // If auto-connect is enabled, connect automatically
  if (settings.autoConnectOnStart) {
    final activeConfig = await singBox.getActiveServerConfig();
    if (activeConfig != null) {
      await singBox.connect(activeConfig.config);
    }
  }
  
  runApp(MyApp());
}
```

## Platform Support

This plugin currently supports:
- Android
- iOS

## Example

See the `example` directory for a complete example app.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
