import 'server_config.dart';

/// Plugin settings
class SingBoxSettings {
  /// Default subnets to bypass (local networks)
  static const List<String> defaultBypassSubnets = [
    '192.168.0.0/16', // Private network
    '10.0.0.0/8', // Private network
    '172.16.0.0/12', // Private network
    '127.0.0.0/8', // Loopback
    '169.254.0.0/16', // Link-local
  ];

  /// Default DNS servers (public DNS)
  static const List<String> defaultDnsServers = [
    '8.8.8.8', // Google DNS
    '1.1.1.1', // Cloudflare DNS
  ];

  /// Automatically connect on application start
  final bool autoConnectOnStart;

  /// Automatically reconnect on connection loss
  final bool autoReconnectOnDisconnect;

  /// Kill switch - block all internet when VPN is disconnected
  final bool killSwitch;

  /// List of apps blocked from using VPN
  /// (apps that should not use VPN)
  final List<String> blockedApps;

  /// List of sites/domains blocked from using VPN
  /// (sites that should not use VPN)
  final List<String> blockedDomains;

  /// List of subnets to bypass (will not use VPN)
  /// Format: CIDR notation (e.g., "192.168.1.0/24", "10.0.0.0/8")
  final List<String> bypassSubnets;

  /// List of DNS servers to use
  /// Format: IP addresses (e.g., "8.8.8.8", "1.1.1.1")
  final List<String> dnsServers;

  /// ID of current active server configuration
  final String? activeServerConfigId;

  /// List of server configurations
  final List<SingBoxServerConfig> serverConfigs;

  const SingBoxSettings({
    this.autoConnectOnStart = false,
    this.autoReconnectOnDisconnect = false,
    this.killSwitch = false,
    this.blockedApps = const [],
    this.blockedDomains = const [],
    this.bypassSubnets = defaultBypassSubnets,
    this.dnsServers = defaultDnsServers,
    this.activeServerConfigId,
    this.serverConfigs = const [],
  });

  /// Creates an object from Map (for deserialization)
  factory SingBoxSettings.fromMap(Map<dynamic, dynamic> map) {
    final serverConfigsList = map['serverConfigs'] as List<dynamic>?;
    return SingBoxSettings(
      autoConnectOnStart: map['autoConnectOnStart'] as bool? ?? false,
      autoReconnectOnDisconnect: map['autoReconnectOnDisconnect'] as bool? ?? false,
      killSwitch: map['killSwitch'] as bool? ?? false,
      blockedApps: (map['blockedApps'] as List<dynamic>?)?.cast<String>() ?? [],
      blockedDomains: (map['blockedDomains'] as List<dynamic>?)?.cast<String>() ?? [],
      bypassSubnets:
          (map['bypassSubnets'] as List<dynamic>?)?.cast<String>() ?? defaultBypassSubnets,
      dnsServers: (map['dnsServers'] as List<dynamic>?)?.cast<String>() ?? defaultDnsServers,
      activeServerConfigId: map['activeServerConfigId'] as String?,
      serverConfigs: serverConfigsList != null
          ? serverConfigsList.map((e) => SingBoxServerConfig.fromMap(e as Map<dynamic, dynamic>)).toList()
          : [],
    );
  }

  /// Converts object to Map (for serialization)
  Map<String, dynamic> toMap() {
    return {
      'autoConnectOnStart': autoConnectOnStart,
      'autoReconnectOnDisconnect': autoReconnectOnDisconnect,
      'killSwitch': killSwitch,
      'blockedApps': blockedApps,
      'blockedDomains': blockedDomains,
      'bypassSubnets': bypassSubnets,
      'dnsServers': dnsServers,
      'activeServerConfigId': activeServerConfigId,
      'serverConfigs': serverConfigs.map((e) => e.toMap()).toList(),
    };
  }

  /// Creates a copy with modified fields
  SingBoxSettings copyWith({
    bool? autoConnectOnStart,
    bool? autoReconnectOnDisconnect,
    bool? killSwitch,
    List<String>? blockedApps,
    List<String>? blockedDomains,
    List<String>? bypassSubnets,
    List<String>? dnsServers,
    String? activeServerConfigId,
    List<SingBoxServerConfig>? serverConfigs,
  }) {
    return SingBoxSettings(
      autoConnectOnStart: autoConnectOnStart ?? this.autoConnectOnStart,
      autoReconnectOnDisconnect: autoReconnectOnDisconnect ?? this.autoReconnectOnDisconnect,
      killSwitch: killSwitch ?? this.killSwitch,
      blockedApps: blockedApps ?? this.blockedApps,
      blockedDomains: blockedDomains ?? this.blockedDomains,
      bypassSubnets: bypassSubnets ?? this.bypassSubnets,
      dnsServers: dnsServers ?? this.dnsServers,
      activeServerConfigId: activeServerConfigId ?? this.activeServerConfigId,
      serverConfigs: serverConfigs ?? this.serverConfigs,
    );
  }

  @override
  String toString() {
    return 'SingBoxSettings(autoConnectOnStart: $autoConnectOnStart, '
        'autoReconnectOnDisconnect: $autoReconnectOnDisconnect, '
        'killSwitch: $killSwitch, '
        'blockedApps: ${blockedApps.length}, '
        'blockedDomains: ${blockedDomains.length}, '
        'bypassSubnets: ${bypassSubnets.length}, '
        'dnsServers: ${dnsServers.length}, '
        'activeServerConfigId: $activeServerConfigId, '
        'serverConfigs: ${serverConfigs.length})';
  }
}
