import 'dart:async';

import 'sing_box_platform_interface.dart';
import 'src/models/connection_status.dart';
import 'src/models/connection_stats.dart';
import 'src/models/ping_result.dart';
import 'src/models/speed_test_result.dart';
import 'src/models/settings.dart';
import 'src/models/server_config.dart';
import 'src/observer/sing_box_observer.dart';

/// Main class for working with sing-box VPN
/// Uses Singleton pattern for access from anywhere in the application
class SingBox {
  /// Private constructor for Singleton implementation
  SingBox._();

  /// Single instance of the class
  static SingBox? _instance;

  /// Initialization flag
  bool _isInitialized = false;

  /// Observer for logging events
  SingBoxObserver _observer = const SingBoxNoOpObserver();

  /// Get SingBox instance (Singleton)
  ///
  /// Must call [initialize()] before use
  ///
  /// Example:
  /// ```dart
  /// final singBox = SingBox.instance;
  /// await singBox.initialize();
  /// ```
  static SingBox get instance {
    _instance ??= SingBox._();
    return _instance!;
  }

  /// Check if plugin is initialized
  bool get isInitialized => _isInitialized;

  /// Set observer for logging events
  ///
  /// Example usage with Talker:
  /// ```dart
  /// import 'package:talker/talker.dart';
  ///
  /// final talker = Talker();
  /// final observer = TalkerObserver(talker);
  /// SingBox.instance.setObserver(observer);
  /// ```
  ///
  /// Or create your own observer:
  /// ```dart
  /// class MyObserver implements SingBoxObserver {
  ///   @override
  ///   void info(String message, [Map<String, dynamic>? data]) {
  ///     print('INFO: $message');
  ///   }
  ///   // ... implement remaining methods
  /// }
  ///
  /// SingBox.instance.setObserver(MyObserver());
  /// ```
  void setObserver(SingBoxObserver observer) {
    _observer = observer;
    _observer.info('Observer set');
  }

  /// Get current observer
  SingBoxObserver get observer => _observer;

  /// Initialize plugin
  ///
  /// Must be called before using other methods, preferably before application start
  ///
  /// Example usage in main():
  /// ```dart
  /// void main() async {
  ///   WidgetsFlutterBinding.ensureInitialized();
  ///   await SingBox.instance.initialize();
  ///   runApp(MyApp());
  /// }
  /// ```
  Future<bool> initialize() async {
    if (_isInitialized) {
      _observer.debug('Already initialized');
      return true;
    }
    _observer.info('Initializing SingBox plugin');
    try {
      final result = await SingBoxPlatform.instance.initialize();
      _isInitialized = result;
      if (result) {
        _observer.info('SingBox plugin initialized successfully');
      } else {
        _observer.warning('SingBox plugin initialization failed');
      }
      return result;
    } catch (e, stackTrace) {
      _observer.error('Failed to initialize SingBox plugin', e, stackTrace);
      _isInitialized = false;
      return false;
    }
  }

  /// Get platform version
  Future<String?> getPlatformVersion() {
    return SingBoxPlatform.instance.getPlatformVersion();
  }

  /// Connect to VPN with specified configuration
  /// [config] - JSON string with server configuration
  Future<bool> connect(String config) async {
    _observer.onConnect(config);
    try {
      final result = await SingBoxPlatform.instance.connect(config);
      if (result) {
        _observer.info('Connected to VPN successfully');
      } else {
        _observer.warning('Failed to connect to VPN');
      }
      return result;
    } catch (e, stackTrace) {
      _observer.onConnectionError(e.toString());
      _observer.error('Error connecting to VPN', e, stackTrace);
      return false;
    }
  }

  /// Disconnect from VPN
  Future<bool> disconnect() async {
    _observer.onDisconnect();
    try {
      final result = await SingBoxPlatform.instance.disconnect();
      if (result) {
        _observer.info('Disconnected from VPN successfully');
      } else {
        _observer.warning('Failed to disconnect from VPN');
      }
      return result;
    } catch (e, stackTrace) {
      _observer.error('Error disconnecting from VPN', e, stackTrace);
      return false;
    }
  }

  /// Get current connection status
  Future<SingBoxConnectionStatus> getConnectionStatus() async {
    try {
      final status = await SingBoxPlatform.instance.getConnectionStatus();
      _observer.onStatusChanged(status.name);
      return status;
    } catch (e, stackTrace) {
      _observer.error('Error getting connection status', e, stackTrace);
      return SingBoxConnectionStatus.disconnected;
    }
  }

  /// Get current connection statistics
  /// Returns statistics including download/upload speed, bytes sent/received, ping, connection duration
  Future<SingBoxConnectionStats> getConnectionStats() async {
    try {
      final stats = await SingBoxPlatform.instance.getConnectionStats();
      _observer.onConnectionStatsChanged(stats);
      return stats;
    } catch (e, stackTrace) {
      _observer.error('Error getting connection stats', e, stackTrace);
      return const SingBoxConnectionStats(
        downloadSpeed: 0,
        uploadSpeed: 0,
        bytesSent: 0,
        bytesReceived: 0,
        connectionDuration: 0,
      );
    }
  }

  /// Measure connection speed
  Future<SingBoxSpeedTestResult> testSpeed() {
    return SingBoxPlatform.instance.testSpeed();
  }

  /// Measure ping to current server
  Future<SingBoxPingResult> pingCurrentServer() {
    return SingBoxPlatform.instance.pingCurrentServer();
  }

  /// Measure ping to specified config
  /// [config] - JSON string with server configuration
  Future<SingBoxPingResult> pingConfig(String config) {
    return SingBoxPlatform.instance.pingConfig(config);
  }

  /// Subscribe to connection status changes
  /// Returns Stream with status updates
  Stream<SingBoxConnectionStatus> watchSingBoxConnectionStatus() {
    return SingBoxPlatform.instance.watchSingBoxConnectionStatus();
  }

  /// Subscribe to connection statistics changes
  /// Returns Stream with statistics updates
  Stream<SingBoxConnectionStats> watchSingBoxConnectionStats() {
    return SingBoxPlatform.instance.watchSingBoxConnectionStats();
  }

  /// Add app to bypass list (will not use VPN)
  /// [packageName] - app package name (Android) or bundle ID (iOS)
  Future<bool> addAppToBypass(String packageName) {
    return SingBoxPlatform.instance.addAppToBypass(packageName);
  }

  /// Remove app from bypass list
  /// [packageName] - app package name (Android) or bundle ID (iOS)
  Future<bool> removeAppFromBypass(String packageName) {
    return SingBoxPlatform.instance.removeAppFromBypass(packageName);
  }

  /// Get list of apps in bypass
  Future<List<String>> getBypassApps() {
    return SingBoxPlatform.instance.getBypassApps();
  }

  /// Add domain/site to bypass list (will not use VPN)
  /// [domain] - domain name or IP address
  Future<bool> addDomainToBypass(String domain) {
    return SingBoxPlatform.instance.addDomainToBypass(domain);
  }

  /// Remove domain/site from bypass list
  /// [domain] - domain name or IP address
  Future<bool> removeDomainFromBypass(String domain) {
    return SingBoxPlatform.instance.removeDomainFromBypass(domain);
  }

  /// Get list of domains/sites in bypass
  Future<List<String>> getBypassDomains() {
    return SingBoxPlatform.instance.getBypassDomains();
  }

  /// Switch current server
  /// Stops current connection, changes configuration and connects to new server
  /// [config] - JSON string with new server configuration
  Future<bool> switchServer(String config) {
    return SingBoxPlatform.instance.switchServer(config);
  }

  // ========== SingBoxSettings ==========

  /// Save settings
  /// [settings] - settings object to save
  Future<bool> saveSingBoxSettings(SingBoxSettings settings) async {
    _observer.info('Saving settings');
    try {
      final result = await SingBoxPlatform.instance.saveSingBoxSettings(settings);
      if (result) {
        _observer.info('SingBoxSettings saved successfully');
      } else {
        _observer.warning('Failed to save settings');
      }
      return result;
    } catch (e, stackTrace) {
      _observer.error('Error saving settings', e, stackTrace);
      return false;
    }
  }

  /// Load settings
  Future<SingBoxSettings> loadSingBoxSettings() {
    return SingBoxPlatform.instance.loadSingBoxSettings();
  }

  /// Get current settings
  Future<SingBoxSettings> getSettings() {
    return SingBoxPlatform.instance.getSettings();
  }

  /// Update individual setting parameter
  /// [key] - parameter key (autoConnectOnStart, autoReconnectOnDisconnect, killSwitch)
  /// [value] - parameter value
  Future<bool> updateSetting(String key, dynamic value) async {
    _observer.onSettingsChanged(key, value);
    try {
      final result = await SingBoxPlatform.instance.updateSetting(key, value);
      if (result) {
        _observer.debug('Setting updated', {'key': key, 'value': value});
      }
      return result;
    } catch (e, stackTrace) {
      _observer.error('Error updating setting', e, stackTrace);
      return false;
    }
  }

  // ========== Server Configurations ==========

  /// Add server configuration
  /// [config] - server configuration
  Future<bool> addServerConfig(SingBoxServerConfig config) async {
    _observer.onServerConfigAdded(config.id, config.name);
    try {
      final result = await SingBoxPlatform.instance.addServerConfig(config);
      if (result) {
        _observer.info('Server config added successfully', {
          'id': config.id,
          'name': config.name,
          'protocol': config.protocol,
        });
      }
      return result;
    } catch (e, stackTrace) {
      _observer.error('Error adding server config', e, stackTrace);
      return false;
    }
  }

  /// Remove server configuration
  /// [configId] - configuration identifier
  Future<bool> removeServerConfig(String configId) async {
    _observer.onServerConfigRemoved(configId);
    try {
      final result = await SingBoxPlatform.instance.removeServerConfig(configId);
      if (result) {
        _observer.info('Server config removed successfully', {'id': configId});
      }
      return result;
    } catch (e, stackTrace) {
      _observer.error('Error removing server config', e, stackTrace);
      return false;
    }
  }

  /// Update server configuration
  /// [config] - updated server configuration
  Future<bool> updateServerConfig(SingBoxServerConfig config) {
    return SingBoxPlatform.instance.updateServerConfig(config);
  }

  /// Get all server configurations
  Future<List<SingBoxServerConfig>> getServerConfigs() {
    return SingBoxPlatform.instance.getServerConfigs();
  }

  /// Get server configuration by ID
  /// [configId] - configuration identifier
  Future<SingBoxServerConfig?> getServerConfig(String configId) {
    return SingBoxPlatform.instance.getServerConfig(configId);
  }

  /// Set active server configuration
  /// [configId] - configuration identifier
  Future<bool> setActiveSingBoxServerConfig(String configId) async {
    _observer.onActiveServerConfigChanged(configId);
    try {
      final result = await SingBoxPlatform.instance.setActiveSingBoxServerConfig(configId);
      if (result) {
        _observer.info('Active server config changed', {'id': configId});
      }
      return result;
    } catch (e, stackTrace) {
      _observer.error('Error setting active server config', e, stackTrace);
      return false;
    }
  }

  /// Get active server configuration
  Future<SingBoxServerConfig?> getActiveSingBoxServerConfig() {
    return SingBoxPlatform.instance.getActiveSingBoxServerConfig();
  }

  // ========== Blocked Apps and Domains ==========

  /// Add app to blocked list
  /// [packageName] - app package name (Android) or bundle ID (iOS)
  Future<bool> addBlockedApp(String packageName) {
    return SingBoxPlatform.instance.addBlockedApp(packageName);
  }

  /// Remove app from blocked list
  /// [packageName] - app package name (Android) or bundle ID (iOS)
  Future<bool> removeBlockedApp(String packageName) {
    return SingBoxPlatform.instance.removeBlockedApp(packageName);
  }

  /// Get list of blocked apps
  Future<List<String>> getBlockedApps() {
    return SingBoxPlatform.instance.getBlockedApps();
  }

  /// Add domain/site to blocked list
  /// [domain] - domain name or IP address
  Future<bool> addBlockedDomain(String domain) {
    return SingBoxPlatform.instance.addBlockedDomain(domain);
  }

  /// Remove domain/site from blocked list
  /// [domain] - domain name or IP address
  Future<bool> removeBlockedDomain(String domain) {
    return SingBoxPlatform.instance.removeBlockedDomain(domain);
  }

  /// Get list of blocked domains/sites
  Future<List<String>> getBlockedDomains() {
    return SingBoxPlatform.instance.getBlockedDomains();
  }

  // ========== Bypass Subnets ==========

  /// Add subnet to bypass list (will not use VPN)
  /// [subnet] - subnet in CIDR notation (e.g., "192.168.1.0/24", "10.0.0.0/8")
  Future<bool> addSubnetToBypass(String subnet) async {
    _observer.info('Adding subnet to bypass', {'subnet': subnet});
    try {
      final result = await SingBoxPlatform.instance.addSubnetToBypass(subnet);
      if (result) {
        _observer.debug('Subnet added to bypass successfully', {'subnet': subnet});
      } else {
        _observer.warning('Failed to add subnet to bypass', {'subnet': subnet});
      }
      return result;
    } catch (e, stackTrace) {
      _observer.error('Error adding subnet to bypass', e, stackTrace);
      return false;
    }
  }

  /// Remove subnet from bypass list
  /// [subnet] - subnet in CIDR notation
  Future<bool> removeSubnetFromBypass(String subnet) async {
    _observer.info('Removing subnet from bypass', {'subnet': subnet});
    try {
      final result = await SingBoxPlatform.instance.removeSubnetFromBypass(subnet);
      if (result) {
        _observer.debug('Subnet removed from bypass successfully', {'subnet': subnet});
      } else {
        _observer.warning('Failed to remove subnet from bypass', {'subnet': subnet});
      }
      return result;
    } catch (e, stackTrace) {
      _observer.error('Error removing subnet from bypass', e, stackTrace);
      return false;
    }
  }

  /// Get list of subnets in bypass
  Future<List<String>> getBypassSubnets() {
    return SingBoxPlatform.instance.getBypassSubnets();
  }

  // ========== DNS Servers ==========

  /// Add DNS server
  /// [dnsServer] - DNS server IP address (e.g., "8.8.8.8", "1.1.1.1")
  Future<bool> addDnsServer(String dnsServer) async {
    _observer.info('Adding DNS server', {'dnsServer': dnsServer});
    try {
      final result = await SingBoxPlatform.instance.addDnsServer(dnsServer);
      if (result) {
        _observer.debug('DNS server added successfully', {'dnsServer': dnsServer});
      } else {
        _observer.warning('Failed to add DNS server', {'dnsServer': dnsServer});
      }
      return result;
    } catch (e, stackTrace) {
      _observer.error('Error adding DNS server', e, stackTrace);
      return false;
    }
  }

  /// Remove DNS server
  /// [dnsServer] - DNS server IP address
  Future<bool> removeDnsServer(String dnsServer) async {
    _observer.info('Removing DNS server', {'dnsServer': dnsServer});
    try {
      final result = await SingBoxPlatform.instance.removeDnsServer(dnsServer);
      if (result) {
        _observer.debug('DNS server removed successfully', {'dnsServer': dnsServer});
      } else {
        _observer.warning('Failed to remove DNS server', {'dnsServer': dnsServer});
      }
      return result;
    } catch (e, stackTrace) {
      _observer.error('Error removing DNS server', e, stackTrace);
      return false;
    }
  }

  /// Get list of DNS servers
  Future<List<String>> getDnsServers() {
    return SingBoxPlatform.instance.getDnsServers();
  }

  /// Set DNS servers (replaces all existing DNS servers)
  /// [dnsServers] - list of DNS server IP addresses
  Future<bool> setDnsServers(List<String> dnsServers) async {
    _observer.info('Setting DNS servers', {'dnsServers': dnsServers});
    try {
      final result = await SingBoxPlatform.instance.setDnsServers(dnsServers);
      if (result) {
        _observer.debug('DNS servers set successfully', {'count': dnsServers.length});
      } else {
        _observer.warning('Failed to set DNS servers', {'count': dnsServers.length});
      }
      return result;
    } catch (e, stackTrace) {
      _observer.error('Error setting DNS servers', e, stackTrace);
      return false;
    }
  }
}
