import 'dart:async';

import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'sing_box_method_channel.dart';
import 'src/models/connection_status.dart';
import 'src/models/connection_stats.dart';
import 'src/models/ping_result.dart';
import 'src/models/speed_test_result.dart';
import 'src/models/settings.dart';
import 'src/models/server_config.dart';
import 'src/models/sing_box_notification.dart';

abstract class SingBoxPlatform extends PlatformInterface {
  /// Constructs a SingBoxPlatform.
  SingBoxPlatform() : super(token: _token);

  static final Object _token = Object();

  static SingBoxPlatform _instance = MethodChannelSingBox();

  /// The default instance of [SingBoxPlatform] to use.
  ///
  /// Defaults to [MethodChannelSingBox].
  static SingBoxPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [SingBoxPlatform] when
  /// they register themselves.
  static set instance(SingBoxPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  /// Initialize plugin
  /// Must be called before using other methods, preferably before application start
  Future<bool> initialize() {
    throw UnimplementedError('initialize() has not been implemented.');
  }

  /// Get platform version
  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }

  /// Connect to VPN with specified configuration
  /// [config] - JSON string with server configuration
  Future<bool> connect(String config) {
    throw UnimplementedError('connect() has not been implemented.');
  }

  /// Disconnect from VPN
  Future<bool> disconnect() {
    throw UnimplementedError('disconnect() has not been implemented.');
  }

  /// Get current connection status
  Future<SingBoxConnectionStatus> getConnectionStatus() {
    throw UnimplementedError('getConnectionStatus() has not been implemented.');
  }

  /// Get current connection statistics
  Future<SingBoxConnectionStats> getConnectionStats() {
    throw UnimplementedError('getConnectionStats() has not been implemented.');
  }

  /// Measure connection speed
  Future<SingBoxSpeedTestResult> testSpeed() {
    throw UnimplementedError('testSpeed() has not been implemented.');
  }

  /// Measure ping to current server
  Future<SingBoxPingResult> pingCurrentServer() {
    throw UnimplementedError('pingCurrentServer() has not been implemented.');
  }


  /// Subscribe to connection status changes
  /// Returns Stream with status updates
  Stream<SingBoxConnectionStatus> watchSingBoxConnectionStatus() {
    throw UnimplementedError('watchSingBoxConnectionStatus() has not been implemented.');
  }

  /// Subscribe to connection statistics changes
  /// Returns Stream with statistics updates
  /// Statistics include: download/upload speed, bytes sent/received, ping, connection duration
  Stream<SingBoxConnectionStats> watchSingBoxConnectionStats() {
    throw UnimplementedError('watchSingBoxConnectionStats() has not been implemented.');
  }

  /// Add app to bypass list (will not use VPN)
  /// [packageName] - app package name (Android) or bundle ID (iOS)
  Future<bool> addAppToBypass(String packageName) {
    throw UnimplementedError('addAppToBypass() has not been implemented.');
  }

  /// Remove app from bypass list
  /// [packageName] - app package name (Android) or bundle ID (iOS)
  Future<bool> removeAppFromBypass(String packageName) {
    throw UnimplementedError('removeAppFromBypass() has not been implemented.');
  }

  /// Get list of apps in bypass
  Future<List<String>> getBypassApps() {
    throw UnimplementedError('getBypassApps() has not been implemented.');
  }

  /// Add domain/site to bypass list (will not use VPN)
  /// [domain] - domain name or IP address
  Future<bool> addDomainToBypass(String domain) {
    throw UnimplementedError('addDomainToBypass() has not been implemented.');
  }

  /// Remove domain/site from bypass list
  /// [domain] - domain name or IP address
  Future<bool> removeDomainFromBypass(String domain) {
    throw UnimplementedError('removeDomainFromBypass() has not been implemented.');
  }

  /// Get list of domains/sites in bypass
  Future<List<String>> getBypassDomains() {
    throw UnimplementedError('getBypassDomains() has not been implemented.');
  }

  /// Switch current server
  /// Stops current connection, changes configuration and connects to new server
  /// [config] - JSON string with new server configuration
  Future<bool> switchServer(String config) {
    throw UnimplementedError('switchServer() has not been implemented.');
  }

  /// Save settings
  /// [settings] - settings object to save
  Future<bool> saveSettings(SingBoxSettings settings) {
    throw UnimplementedError('saveSettings() has not been implemented.');
  }

  /// Load settings
  Future<SingBoxSettings> loadSettings() {
    throw UnimplementedError('loadSettings() has not been implemented.');
  }

  /// Get current settings
  Future<SingBoxSettings> getSettings() {
    throw UnimplementedError('getSettings() has not been implemented.');
  }

  /// Update individual setting parameter
  /// [key] - parameter key (autoConnectOnStart, autoReconnectOnDisconnect, killSwitch)
  /// [value] - parameter value
  Future<bool> updateSetting(String key, dynamic value) {
    throw UnimplementedError('updateSetting() has not been implemented.');
  }

  /// Add server configuration
  /// [config] - server configuration
  Future<bool> addServerConfig(SingBoxServerConfig config) {
    throw UnimplementedError('addServerConfig() has not been implemented.');
  }

  /// Remove server configuration
  /// [configId] - configuration identifier
  Future<bool> removeServerConfig(String configId) {
    throw UnimplementedError('removeServerConfig() has not been implemented.');
  }

  /// Update server configuration
  /// [config] - updated server configuration
  Future<bool> updateServerConfig(SingBoxServerConfig config) {
    throw UnimplementedError('updateServerConfig() has not been implemented.');
  }

  /// Get all server configurations
  Future<List<SingBoxServerConfig>> getServerConfigs() {
    throw UnimplementedError('getServerConfigs() has not been implemented.');
  }

  /// Get server configuration by ID
  /// [configId] - configuration identifier
  Future<SingBoxServerConfig?> getServerConfig(String configId) {
    throw UnimplementedError('getServerConfig() has not been implemented.');
  }

  /// Set active server configuration
  /// [configId] - configuration identifier
  Future<bool> setActiveServerConfig(String configId) {
    throw UnimplementedError('setActiveServerConfig() has not been implemented.');
  }

  /// Get active server configuration
  Future<SingBoxServerConfig?> getActiveSingBoxServerConfig() {
    throw UnimplementedError('getActiveSingBoxServerConfig() has not been implemented.');
  }

  /// Add app to blocked list
  /// [packageName] - app package name (Android) or bundle ID (iOS)
  Future<bool> addBlockedApp(String packageName) {
    throw UnimplementedError('addBlockedApp() has not been implemented.');
  }

  /// Remove app from blocked list
  /// [packageName] - app package name (Android) or bundle ID (iOS)
  Future<bool> removeBlockedApp(String packageName) {
    throw UnimplementedError('removeBlockedApp() has not been implemented.');
  }

  /// Get list of blocked apps
  Future<List<String>> getBlockedApps() {
    throw UnimplementedError('getBlockedApps() has not been implemented.');
  }

  /// Add domain/site to blocked list
  /// [domain] - domain name or IP address
  Future<bool> addBlockedDomain(String domain) {
    throw UnimplementedError('addBlockedDomain() has not been implemented.');
  }

  /// Remove domain/site from blocked list
  /// [domain] - domain name or IP address
  Future<bool> removeBlockedDomain(String domain) {
    throw UnimplementedError('removeBlockedDomain() has not been implemented.');
  }

  /// Get list of blocked domains/sites
  Future<List<String>> getBlockedDomains() {
    throw UnimplementedError('getBlockedDomains() has not been implemented.');
  }

  // ========== Bypass Subnets ==========

  /// Add subnet to bypass list (will not use VPN)
  /// [subnet] - subnet in CIDR notation (e.g., "192.168.1.0/24", "10.0.0.0/8")
  Future<bool> addSubnetToBypass(String subnet) {
    throw UnimplementedError('addSubnetToBypass() has not been implemented.');
  }

  /// Remove subnet from bypass list
  /// [subnet] - subnet in CIDR notation
  Future<bool> removeSubnetFromBypass(String subnet) {
    throw UnimplementedError('removeSubnetFromBypass() has not been implemented.');
  }

  /// Get list of subnets in bypass
  Future<List<String>> getBypassSubnets() {
    throw UnimplementedError('getBypassSubnets() has not been implemented.');
  }

  // ========== DNS Servers ==========

  /// Add DNS server
  /// [dnsServer] - DNS server IP address (e.g., "8.8.8.8", "1.1.1.1")
  Future<bool> addDnsServer(String dnsServer) {
    throw UnimplementedError('addDnsServer() has not been implemented.');
  }

  /// Remove DNS server
  /// [dnsServer] - DNS server IP address
  Future<bool> removeDnsServer(String dnsServer) {
    throw UnimplementedError('removeDnsServer() has not been implemented.');
  }

  /// Get list of DNS servers
  Future<List<String>> getDnsServers() {
    throw UnimplementedError('getDnsServers() has not been implemented.');
  }

  /// Set DNS servers (replaces all existing DNS servers)
  /// [dnsServers] - list of DNS server IP addresses
  Future<bool> setDnsServers(List<String> dnsServers) {
    throw UnimplementedError('setDnsServers() has not been implemented.');
  }

  /// Subscribe to notifications from sing-box
  /// Returns Stream with notification updates
  Stream<SingBoxNotification> watchNotifications() {
    throw UnimplementedError('watchNotifications() has not been implemented.');
  }
}
