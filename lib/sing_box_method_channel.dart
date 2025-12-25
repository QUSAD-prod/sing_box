import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'sing_box_platform_interface.dart';
import 'src/models/connection_status.dart';
import 'src/models/connection_stats.dart';
import 'src/models/ping_result.dart';
import 'src/models/speed_test_result.dart';
import 'src/models/settings.dart';
import 'src/models/server_config.dart';

/// An implementation of [SingBoxPlatform] that uses method channels.
class MethodChannelSingBox extends SingBoxPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('sing_box');

  /// Event channel for connection status updates
  @visibleForTesting
  final statusEventChannel = const EventChannel('sing_box/status');

  /// Event channel for connection stats updates
  @visibleForTesting
  final statsEventChannel = const EventChannel('sing_box/stats');

  @override
  Future<bool> initialize() async {
    try {
      final result = await methodChannel.invokeMethod<bool>('initialize');
      return result ?? false;
    } catch (e) {
      debugPrint('Error initializing sing_box: $e');
      return false;
    }
  }

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>('getPlatformVersion');
    return version;
  }

  @override
  Future<bool> connect(String config) async {
    try {
      final result = await methodChannel.invokeMethod<bool>('connect', {'config': config});
      return result ?? false;
    } catch (e) {
      debugPrint('Error connecting to VPN: $e');
      return false;
    }
  }

  @override
  Future<bool> disconnect() async {
    try {
      final result = await methodChannel.invokeMethod<bool>('disconnect');
      return result ?? false;
    } catch (e) {
      debugPrint('Error disconnecting from VPN: $e');
      return false;
    }
  }

  @override
  Future<SingBoxConnectionStatus> getConnectionStatus() async {
    try {
      final statusString = await methodChannel.invokeMethod<String>('getConnectionStatus');
      if (statusString != null) {
        return SingBoxConnectionStatusExtension.fromString(statusString);
      }
      return SingBoxConnectionStatus.disconnected;
    } catch (e) {
      debugPrint('Error getting connection status: $e');
      return SingBoxConnectionStatus.disconnected;
    }
  }

  @override
  Future<SingBoxConnectionStats> getConnectionStats() async {
    try {
      final statsMap = await methodChannel.invokeMethod<Map<dynamic, dynamic>>(
        'getConnectionStats',
      );
      if (statsMap != null) {
        return SingBoxConnectionStats.fromMap(statsMap);
      }
      return const SingBoxConnectionStats(
        downloadSpeed: 0,
        uploadSpeed: 0,
        bytesSent: 0,
        bytesReceived: 0,
        connectionDuration: 0,
      );
    } catch (e) {
      debugPrint('Error getting connection stats: $e');
      return const SingBoxConnectionStats(
        downloadSpeed: 0,
        uploadSpeed: 0,
        bytesSent: 0,
        bytesReceived: 0,
        connectionDuration: 0,
      );
    }
  }

  @override
  Future<SingBoxSpeedTestResult> testSpeed() async {
    try {
      final resultMap = await methodChannel.invokeMethod<Map<dynamic, dynamic>>('testSpeed');
      if (resultMap != null) {
        return SingBoxSpeedTestResult.fromMap(resultMap);
      }
      return const SingBoxSpeedTestResult(
        downloadSpeed: 0,
        uploadSpeed: 0,
        success: false,
        errorMessage: 'Failed to get speed test result',
      );
    } catch (e) {
      debugPrint('Error testing speed: $e');
      return SingBoxSpeedTestResult(
        downloadSpeed: 0,
        uploadSpeed: 0,
        success: false,
        errorMessage: e.toString(),
      );
    }
  }

  @override
  Future<SingBoxPingResult> pingCurrentServer() async {
    try {
      final resultMap = await methodChannel.invokeMethod<Map<dynamic, dynamic>>(
        'pingCurrentServer',
      );
      if (resultMap != null) {
        return SingBoxPingResult.fromMap(resultMap);
      }
      return const SingBoxPingResult(ping: 0, success: false, errorMessage: 'Failed to get ping result');
    } catch (e) {
      debugPrint('Error pinging current server: $e');
      return SingBoxPingResult(ping: 0, success: false, errorMessage: e.toString());
    }
  }

  @override
  Future<SingBoxPingResult> pingConfig(String config) async {
    try {
      final resultMap = await methodChannel.invokeMethod<Map<dynamic, dynamic>>('pingConfig', {
        'config': config,
      });
      if (resultMap != null) {
        return SingBoxPingResult.fromMap(resultMap);
      }
      return const SingBoxPingResult(ping: 0, success: false, errorMessage: 'Failed to get ping result');
    } catch (e) {
      debugPrint('Error pinging config: $e');
      return SingBoxPingResult(ping: 0, success: false, errorMessage: e.toString());
    }
  }

  @override
  Stream<SingBoxConnectionStatus> watchSingBoxConnectionStatus() {
    try {
      return statusEventChannel
          .receiveBroadcastStream()
          .map((dynamic event) {
            if (event is String) {
              return SingBoxConnectionStatusExtension.fromString(event);
            }
            return SingBoxConnectionStatus.disconnected;
          })
          .handleError((error) {
            debugPrint('Error in connection status stream: $error');
          });
    } catch (e) {
      debugPrint('Error creating connection status stream: $e');
      return Stream.value(SingBoxConnectionStatus.disconnected);
    }
  }

  @override
  Stream<SingBoxConnectionStats> watchSingBoxConnectionStats() {
    try {
      return statsEventChannel
          .receiveBroadcastStream()
          .map((dynamic event) {
            if (event is Map) {
              return SingBoxConnectionStats.fromMap(event);
            }
            return const SingBoxConnectionStats(
              downloadSpeed: 0,
              uploadSpeed: 0,
              bytesSent: 0,
              bytesReceived: 0,
              connectionDuration: 0,
            );
          })
          .handleError((error) {
            debugPrint('Error in connection stats stream: $error');
          });
    } catch (e) {
      debugPrint('Error creating connection stats stream: $e');
      return Stream.value(
        const SingBoxConnectionStats(
          downloadSpeed: 0,
          uploadSpeed: 0,
          bytesSent: 0,
          bytesReceived: 0,
          connectionDuration: 0,
        ),
      );
    }
  }

  @override
  Future<bool> addAppToBypass(String packageName) async {
    try {
      final result = await methodChannel.invokeMethod<bool>('addAppToBypass', {
        'packageName': packageName,
      });
      return result ?? false;
    } catch (e) {
      debugPrint('Error adding app to bypass: $e');
      return false;
    }
  }

  @override
  Future<bool> removeAppFromBypass(String packageName) async {
    try {
      final result = await methodChannel.invokeMethod<bool>('removeAppFromBypass', {
        'packageName': packageName,
      });
      return result ?? false;
    } catch (e) {
      debugPrint('Error removing app from bypass: $e');
      return false;
    }
  }

  @override
  Future<List<String>> getBypassApps() async {
    try {
      final apps = await methodChannel.invokeMethod<List<dynamic>>('getBypassApps');
      if (apps != null) {
        return apps.cast<String>();
      }
      return [];
    } catch (e) {
      debugPrint('Error getting bypass apps: $e');
      return [];
    }
  }

  @override
  Future<bool> addDomainToBypass(String domain) async {
    try {
      final result = await methodChannel.invokeMethod<bool>('addDomainToBypass', {
        'domain': domain,
      });
      return result ?? false;
    } catch (e) {
      debugPrint('Error adding domain to bypass: $e');
      return false;
    }
  }

  @override
  Future<bool> removeDomainFromBypass(String domain) async {
    try {
      final result = await methodChannel.invokeMethod<bool>('removeDomainFromBypass', {
        'domain': domain,
      });
      return result ?? false;
    } catch (e) {
      debugPrint('Error removing domain from bypass: $e');
      return false;
    }
  }

  @override
  Future<List<String>> getBypassDomains() async {
    try {
      final domains = await methodChannel.invokeMethod<List<dynamic>>('getBypassDomains');
      if (domains != null) {
        return domains.cast<String>();
      }
      return [];
    } catch (e) {
      debugPrint('Error getting bypass domains: $e');
      return [];
    }
  }

  @override
  Future<bool> switchServer(String config) async {
    try {
      final result = await methodChannel.invokeMethod<bool>('switchServer', {'config': config});
      return result ?? false;
    } catch (e) {
      debugPrint('Error switching server: $e');
      return false;
    }
  }

  @override
  Future<bool> saveSettings(SingBoxSettings settings) async {
    try {
      final result = await methodChannel.invokeMethod<bool>('saveSettings', {
        'settings': settings.toMap(),
      });
      return result ?? false;
    } catch (e) {
      debugPrint('Error saving settings: $e');
      return false;
    }
  }

  @override
  Future<SingBoxSettings> loadSettings() async {
    try {
      final settingsMap = await methodChannel.invokeMethod<Map<dynamic, dynamic>>('loadSettings');
      if (settingsMap != null) {
        return SingBoxSettings.fromMap(settingsMap);
      }
      return const SingBoxSettings();
    } catch (e) {
      debugPrint('Error loading settings: $e');
      return const SingBoxSettings();
    }
  }

  @override
  Future<SingBoxSettings> getSettings() async {
    try {
      final settingsMap = await methodChannel.invokeMethod<Map<dynamic, dynamic>>('getSettings');
      if (settingsMap != null) {
        return SingBoxSettings.fromMap(settingsMap);
      }
      return const SingBoxSettings();
    } catch (e) {
      debugPrint('Error getting settings: $e');
      return const SingBoxSettings();
    }
  }

  @override
  Future<bool> updateSetting(String key, dynamic value) async {
    try {
      final result = await methodChannel.invokeMethod<bool>('updateSetting', {
        'key': key,
        'value': value,
      });
      return result ?? false;
    } catch (e) {
      debugPrint('Error updating setting: $e');
      return false;
    }
  }

  @override
  Future<bool> addServerConfig(SingBoxServerConfig config) async {
    try {
      final result = await methodChannel.invokeMethod<bool>('addServerConfig', {
        'config': config.toMap(),
      });
      return result ?? false;
    } catch (e) {
      debugPrint('Error adding server config: $e');
      return false;
    }
  }

  @override
  Future<bool> removeServerConfig(String configId) async {
    try {
      final result = await methodChannel.invokeMethod<bool>('removeServerConfig', {
        'configId': configId,
      });
      return result ?? false;
    } catch (e) {
      debugPrint('Error removing server config: $e');
      return false;
    }
  }

  @override
  Future<bool> updateServerConfig(SingBoxServerConfig config) async {
    try {
      final result = await methodChannel.invokeMethod<bool>('updateServerConfig', {
        'config': config.toMap(),
      });
      return result ?? false;
    } catch (e) {
      debugPrint('Error updating server config: $e');
      return false;
    }
  }

  @override
  Future<List<SingBoxServerConfig>> getServerConfigs() async {
    try {
      final configsList = await methodChannel.invokeMethod<List<dynamic>>('getServerConfigs');
      if (configsList != null) {
        return configsList.map((e) => SingBoxServerConfig.fromMap(e as Map<dynamic, dynamic>)).toList();
      }
      return [];
    } catch (e) {
      debugPrint('Error getting server configs: $e');
      return [];
    }
  }

  @override
  Future<SingBoxServerConfig?> getServerConfig(String configId) async {
    try {
      final configMap = await methodChannel.invokeMethod<Map<dynamic, dynamic>>('getServerConfig', {
        'configId': configId,
      });
      if (configMap != null) {
        return SingBoxServerConfig.fromMap(configMap);
      }
      return null;
    } catch (e) {
      debugPrint('Error getting server config: $e');
      return null;
    }
  }

  @override
  Future<bool> setActiveServerConfig(String configId) async {
    try {
      final result = await methodChannel.invokeMethod<bool>('setActiveServerConfig', {
        'configId': configId,
      });
      return result ?? false;
    } catch (e) {
      debugPrint('Error setting active server config: $e');
      return false;
    }
  }

  @override
  Future<SingBoxServerConfig?> getActiveSingBoxServerConfig() async {
    try {
      final configMap = await methodChannel.invokeMethod<Map<dynamic, dynamic>>(
        'getActiveSingBoxServerConfig',
      );
      if (configMap != null) {
        return SingBoxServerConfig.fromMap(configMap);
      }
      return null;
    } catch (e) {
      debugPrint('Error getting active server config: $e');
      return null;
    }
  }

  @override
  Future<bool> addBlockedApp(String packageName) async {
    try {
      final result = await methodChannel.invokeMethod<bool>('addBlockedApp', {
        'packageName': packageName,
      });
      return result ?? false;
    } catch (e) {
      debugPrint('Error adding blocked app: $e');
      return false;
    }
  }

  @override
  Future<bool> removeBlockedApp(String packageName) async {
    try {
      final result = await methodChannel.invokeMethod<bool>('removeBlockedApp', {
        'packageName': packageName,
      });
      return result ?? false;
    } catch (e) {
      debugPrint('Error removing blocked app: $e');
      return false;
    }
  }

  @override
  Future<List<String>> getBlockedApps() async {
    try {
      final apps = await methodChannel.invokeMethod<List<dynamic>>('getBlockedApps');
      if (apps != null) {
        return apps.cast<String>();
      }
      return [];
    } catch (e) {
      debugPrint('Error getting blocked apps: $e');
      return [];
    }
  }

  @override
  Future<bool> addBlockedDomain(String domain) async {
    try {
      final result = await methodChannel.invokeMethod<bool>('addBlockedDomain', {'domain': domain});
      return result ?? false;
    } catch (e) {
      debugPrint('Error adding blocked domain: $e');
      return false;
    }
  }

  @override
  Future<bool> removeBlockedDomain(String domain) async {
    try {
      final result = await methodChannel.invokeMethod<bool>('removeBlockedDomain', {
        'domain': domain,
      });
      return result ?? false;
    } catch (e) {
      debugPrint('Error removing blocked domain: $e');
      return false;
    }
  }

  @override
  Future<List<String>> getBlockedDomains() async {
    try {
      final domains = await methodChannel.invokeMethod<List<dynamic>>('getBlockedDomains');
      if (domains != null) {
        return domains.cast<String>();
      }
      return [];
    } catch (e) {
      debugPrint('Error getting blocked domains: $e');
      return [];
    }
  }

  // ========== Bypass Subnets ==========

  @override
  Future<bool> addSubnetToBypass(String subnet) async {
    try {
      final result = await methodChannel.invokeMethod<bool>('addSubnetToBypass', {
        'subnet': subnet,
      });
      return result ?? false;
    } catch (e) {
      debugPrint('Error adding subnet to bypass: $e');
      return false;
    }
  }

  @override
  Future<bool> removeSubnetFromBypass(String subnet) async {
    try {
      final result = await methodChannel.invokeMethod<bool>('removeSubnetFromBypass', {
        'subnet': subnet,
      });
      return result ?? false;
    } catch (e) {
      debugPrint('Error removing subnet from bypass: $e');
      return false;
    }
  }

  @override
  Future<List<String>> getBypassSubnets() async {
    try {
      final subnets = await methodChannel.invokeMethod<List<dynamic>>('getBypassSubnets');
      if (subnets != null) {
        return subnets.cast<String>();
      }
      return [];
    } catch (e) {
      debugPrint('Error getting bypass subnets: $e');
      return [];
    }
  }

  // ========== DNS Servers ==========

  @override
  Future<bool> addDnsServer(String dnsServer) async {
    try {
      final result = await methodChannel.invokeMethod<bool>('addDnsServer', {
        'dnsServer': dnsServer,
      });
      return result ?? false;
    } catch (e) {
      debugPrint('Error adding DNS server: $e');
      return false;
    }
  }

  @override
  Future<bool> removeDnsServer(String dnsServer) async {
    try {
      final result = await methodChannel.invokeMethod<bool>('removeDnsServer', {
        'dnsServer': dnsServer,
      });
      return result ?? false;
    } catch (e) {
      debugPrint('Error removing DNS server: $e');
      return false;
    }
  }

  @override
  Future<List<String>> getDnsServers() async {
    try {
      final dnsServers = await methodChannel.invokeMethod<List<dynamic>>('getDnsServers');
      if (dnsServers != null) {
        return dnsServers.cast<String>();
      }
      return [];
    } catch (e) {
      debugPrint('Error getting DNS servers: $e');
      return [];
    }
  }

  @override
  Future<bool> setDnsServers(List<String> dnsServers) async {
    try {
      final result = await methodChannel.invokeMethod<bool>('setDnsServers', {
        'dnsServers': dnsServers,
      });
      return result ?? false;
    } catch (e) {
      debugPrint('Error setting DNS servers: $e');
      return false;
    }
  }
}
