/// Server configuration with protocol
class SingBoxServerConfig {
  /// Unique configuration identifier
  final String id;

  /// Configuration name
  final String name;

  /// JSON string with server configuration
  final String config;

  /// Protocol (e.g.: vmess, vless, shadowsocks, trojan, etc.)
  final String protocol;

  /// Server (hostname or IP)
  final String server;

  /// Port
  final int port;

  /// Whether this configuration is enabled
  final bool enabled;

  const SingBoxServerConfig({
    required this.id,
    required this.name,
    required this.config,
    required this.protocol,
    required this.server,
    required this.port,
    this.enabled = true,
  });

  /// Creates an object from Map (for deserialization)
  factory SingBoxServerConfig.fromMap(Map<dynamic, dynamic> map) {
    return SingBoxServerConfig(
      id: map['id'] as String? ?? '',
      name: map['name'] as String? ?? '',
      config: map['config'] as String? ?? '',
      protocol: map['protocol'] as String? ?? '',
      server: map['server'] as String? ?? '',
      port: map['port'] as int? ?? 0,
      enabled: map['enabled'] as bool? ?? true,
    );
  }

  /// Converts object to Map (for serialization)
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'config': config,
      'protocol': protocol,
      'server': server,
      'port': port,
      'enabled': enabled,
    };
  }

  /// Creates a copy with modified fields
  SingBoxServerConfig copyWith({
    String? id,
    String? name,
    String? config,
    String? protocol,
    String? server,
    int? port,
    bool? enabled,
  }) {
    return SingBoxServerConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      config: config ?? this.config,
      protocol: protocol ?? this.protocol,
      server: server ?? this.server,
      port: port ?? this.port,
      enabled: enabled ?? this.enabled,
    );
  }

  @override
  String toString() {
    return 'SingBoxServerConfig(id: $id, name: $name, protocol: $protocol, server: $server:$port, enabled: $enabled)';
  }
}
