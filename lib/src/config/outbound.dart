import 'dart:convert';

import 'internal/json_utils.dart';
import 'share_link.dart';

/// A proxy server as a sing-box outbound (or endpoint) object, usually
/// produced by `SingBoxShareLink.parse` or `SingBoxShareLink.parseSubscription`.
///
/// [json] is the sing-box object, ready to be passed to
/// `SingBoxConfigBuilder.build`. The other fields are convenience accessors
/// extracted from it.
///
/// WireGuard is an **endpoint** since sing-box 1.11 (the WireGuard outbound
/// was removed in 1.13): [isEndpoint] is `true` for it and the builder places
/// it under `endpoints` instead of `outbounds`.
///
/// ```dart
/// final outbound = SingBoxShareLink.parse('trojan://secret@example.com:443#My server');
/// print(outbound.tag);        // My server
/// print(outbound.toJson());   // {"type":"trojan","tag":"My server",...}
/// ```
class SingBoxOutbound {
  SingBoxOutbound._({
    required this.type,
    required this.tag,
    required this.server,
    required this.serverPort,
    required this.name,
    required this.json,
    required this.link,
  });

  /// Creates an outbound from a sing-box outbound or endpoint object.
  ///
  /// The object is deep copied. [type] and [tag] are read from it (a missing
  /// tag becomes `<type>`), [server]/[serverPort] from `server`/`server_port`
  /// or, for WireGuard endpoints, from the first peer.
  ///
  /// Throws an [ArgumentError] when the object has no `type`.
  factory SingBoxOutbound.fromJson(
    Map<dynamic, dynamic> json, {
    String? name,
    String? link,
  }) {
    final copy = deepCopyMap(json);
    final type = readString(copy['type']);
    if (type == null) {
      throw ArgumentError.value(json, 'json', 'Outbound object has no "type"');
    }
    var tag = readString(copy['tag']);
    if (tag == null) {
      tag = type;
      copy['tag'] = tag;
    }
    var server = readString(copy['server']);
    var port = readInt(copy['server_port']);
    final peers = copy['peers'];
    if (server == null && peers is List && peers.isNotEmpty) {
      final peer = peers.first;
      if (peer is Map) {
        server = readString(peer['address']);
        port = readInt(peer['port']);
      }
    }
    if (port == null && copy['server_ports'] != null) {
      final ports = readStringList(copy['server_ports']);
      if (ports.isNotEmpty) {
        port = int.tryParse(ports.first.split(RegExp('[:-]')).first);
      }
    }
    return SingBoxOutbound._(
      type: type,
      tag: tag,
      server: server,
      serverPort: port,
      name: name,
      json: copy,
      link: link,
    );
  }

  /// Outbound types that are not proxies (groups and special outbounds).
  static const nonProxyTypes = {
    'direct',
    'block',
    'dns',
    'selector',
    'urltest',
  };

  /// Types that sing-box configures under `endpoints`.
  static const endpointTypes = {'wireguard', 'tailscale'};

  /// Whether [type] is a proxy protocol (not a group or special outbound).
  static bool isProxyType(String type) => !nonProxyTypes.contains(type);

  /// sing-box protocol type, e.g. `vless`, `shadowsocks`, `wireguard`.
  final String type;

  /// Unique tag (the outbound name inside the configuration).
  final String tag;

  /// Server host name or IP address.
  final String? server;

  /// Server port (the first port for port hopping configurations).
  final int? serverPort;

  /// Human readable name from the share link (`#fragment`, VMess `ps`).
  final String? name;

  /// The sing-box outbound (or endpoint) object.
  final Map<String, dynamic> json;

  /// The share link this outbound was parsed from, if any.
  final String? link;

  /// Whether this is a sing-box endpoint (WireGuard) that belongs under
  /// `endpoints` instead of `outbounds`.
  bool get isEndpoint => endpointTypes.contains(type);

  /// [name] if present, otherwise [tag].
  String get displayName => name ?? tag;

  /// Returns a copy whose tag (and `json['tag']`) is [tag].
  SingBoxOutbound withTag(String tag) {
    final copy = deepCopyMap(json);
    copy['tag'] = tag;
    return SingBoxOutbound._(
      type: type,
      tag: tag,
      server: server,
      serverPort: serverPort,
      name: name,
      json: copy,
      link: link,
    );
  }

  /// The sing-box object as a JSON string.
  String toJson() => jsonEncode(json);

  /// Converts the outbound to a share link (see `SingBoxShareLink.toLink`).
  ///
  /// Throws an [UnsupportedError] for protocols without a link format.
  String toLink() => SingBoxShareLink.toLink(json);

  @override
  bool operator ==(Object other) =>
      other is SingBoxOutbound &&
      other.name == name &&
      other.link == link &&
      other.toJson() == toJson();

  @override
  int get hashCode => Object.hash(name, link, toJson());

  @override
  String toString() {
    final address = server == null
        ? ''
        : ', server: ${server!.contains(':') ? '[$server]' : server}'
              '${serverPort == null ? '' : ':$serverPort'}';
    return 'SingBoxOutbound(type: $type, tag: $tag$address)';
  }
}
