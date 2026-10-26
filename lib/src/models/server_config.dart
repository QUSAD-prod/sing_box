import 'dart:convert';

/// A saved server profile.
///
/// [config] holds either
///
/// * a **single sing-box outbound** object, e.g.
///   `{"type": "vless", "tag": "my-server", "server": "...", ...}` - the
///   plugin wraps it into a complete configuration with TUN, DNS and routing
///   (see `SingBoxConfigBuilder`); this is what `SingBoxServerConfig.fromLink`
///   produces, or
/// * a **complete sing-box configuration** (with `outbounds`, usually also
///   `inbounds`, `dns` and `route`) - used as is, with the stored routing
///   rules applied on top.
///
/// Profiles are persisted with `SingBox.addServerConfig()` and friends.
class SingBoxServerConfig {
  /// Creates a server profile.
  const SingBoxServerConfig({
    required this.id,
    required this.name,
    required this.config,
    required this.protocol,
    required this.server,
    required this.port,
    this.enabled = true,
    this.link,
    this.subscriptionId,
  });

  /// Creates a profile from a sing-box outbound object.
  ///
  /// [id] defaults to the outbound tag and [name] to [id].
  factory SingBoxServerConfig.fromOutbound(
    Map<String, dynamic> outbound, {
    String? id,
    String? name,
    String? link,
    String? subscriptionId,
  }) {
    final tag = outbound['tag'] as String?;
    final resolvedId = id ?? tag ?? _generateId();
    return SingBoxServerConfig(
      id: resolvedId,
      name: name ?? tag ?? resolvedId,
      config: jsonEncode(outbound),
      protocol: outbound['type'] as String? ?? '',
      server: outbound['server'] as String? ?? '',
      port: (outbound['server_port'] as num?)?.toInt() ?? 0,
      link: link,
      subscriptionId: subscriptionId,
    );
  }

  /// Creates a profile from a complete sing-box configuration JSON string.
  ///
  /// [protocol], [server] and [port] are taken from the first proxy outbound
  /// when not given.
  factory SingBoxServerConfig.fromFullConfig(
    String config, {
    required String id,
    required String name,
    String? protocol,
    String? server,
    int? port,
  }) {
    Map<String, dynamic>? first;
    try {
      final decoded = jsonDecode(config);
      if (decoded is Map && decoded['outbounds'] is List) {
        for (final o in decoded['outbounds'] as List) {
          if (o is Map && !_nonProxyTypes.contains(o['type'])) {
            first = Map<String, dynamic>.from(o);
            break;
          }
        }
      }
    } on FormatException {
      // Keep the defaults; the config is validated when connecting.
    }
    return SingBoxServerConfig(
      id: id,
      name: name,
      config: config,
      protocol: protocol ?? first?['type'] as String? ?? 'custom',
      server: server ?? first?['server'] as String? ?? '',
      port: port ?? (first?['server_port'] as num?)?.toInt() ?? 0,
    );
  }

  /// Creates an object from a map (for deserialization).
  factory SingBoxServerConfig.fromMap(Map<dynamic, dynamic> map) {
    return SingBoxServerConfig(
      id: map['id'] as String? ?? '',
      name: map['name'] as String? ?? '',
      config: map['config'] as String? ?? '',
      protocol: map['protocol'] as String? ?? '',
      server: map['server'] as String? ?? '',
      port: (map['port'] as num?)?.toInt() ?? 0,
      enabled: map['enabled'] as bool? ?? true,
      link: map['link'] as String?,
      subscriptionId: map['subscriptionId'] as String?,
    );
  }

  static const _nonProxyTypes = {'direct', 'block', 'dns', 'selector', 'urltest'};

  static int _counter = 0;

  static String _generateId() =>
      'server-${DateTime.now().microsecondsSinceEpoch}-${_counter++}';

  /// Unique identifier.
  final String id;

  /// Display name.
  final String name;

  /// JSON: a single outbound object or a complete sing-box configuration.
  final String config;

  /// Protocol, e.g. `vless`, `vmess`, `trojan`, `shadowsocks`,
  /// `hysteria2`, `tuic`, `wireguard` or `custom`.
  final String protocol;

  /// Server host name or IP address.
  final String server;

  /// Server port.
  final int port;

  /// Whether the profile is enabled (disabled profiles are skipped by
  /// `SingBox.connectToServers()`).
  final bool enabled;

  /// The share link the profile was imported from, if any.
  final String? link;

  /// Identifier of the subscription the profile belongs to, if any.
  final String? subscriptionId;

  /// Whether [config] is a complete sing-box configuration rather than a
  /// single outbound.
  bool get isFullConfig {
    try {
      final decoded = jsonDecode(config);
      return decoded is Map &&
          (decoded.containsKey('outbounds') ||
              decoded.containsKey('inbounds') ||
              decoded.containsKey('route'));
    } on FormatException {
      return false;
    }
  }

  /// The outbound object when [config] is a single outbound, otherwise
  /// `null`.
  Map<String, dynamic>? get outbound {
    if (isFullConfig) return null;
    try {
      final decoded = jsonDecode(config);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } on FormatException {
      return null;
    }
  }

  /// Converts the object to a map (for serialization).
  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'config': config,
    'protocol': protocol,
    'server': server,
    'port': port,
    'enabled': enabled,
    if (link != null) 'link': link,
    if (subscriptionId != null) 'subscriptionId': subscriptionId,
  };

  /// Creates a copy with modified fields.
  SingBoxServerConfig copyWith({
    String? id,
    String? name,
    String? config,
    String? protocol,
    String? server,
    int? port,
    bool? enabled,
    String? link,
    String? subscriptionId,
  }) {
    return SingBoxServerConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      config: config ?? this.config,
      protocol: protocol ?? this.protocol,
      server: server ?? this.server,
      port: port ?? this.port,
      enabled: enabled ?? this.enabled,
      link: link ?? this.link,
      subscriptionId: subscriptionId ?? this.subscriptionId,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SingBoxServerConfig &&
      other.id == id &&
      other.name == name &&
      other.config == config &&
      other.protocol == protocol &&
      other.server == server &&
      other.port == port &&
      other.enabled == enabled &&
      other.link == link &&
      other.subscriptionId == subscriptionId;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    config,
    protocol,
    server,
    port,
    enabled,
    link,
    subscriptionId,
  );

  @override
  String toString() =>
      'SingBoxServerConfig(id: $id, name: $name, protocol: $protocol, '
      'server: $server:$port, enabled: $enabled)';
}
