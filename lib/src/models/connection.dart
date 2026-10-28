/// A network connection tracked by the sing-box core.
///
/// Delivered by `SingBox.watchConnections()`; contains both active and
/// recently closed connections.
class SingBoxConnection {
  /// Creates a connection.
  const SingBoxConnection({
    required this.id,
    required this.network,
    required this.destination,
    this.inbound = '',
    this.inboundType = '',
    this.ipVersion = 4,
    this.source = '',
    this.domain = '',
    this.protocol = '',
    this.user = '',
    this.fromOutbound = '',
    required this.createdAt,
    this.closedAt,
    this.uploadSpeed = 0,
    this.downloadSpeed = 0,
    this.uploadTotal = 0,
    this.downloadTotal = 0,
    this.rule = '',
    this.outbound = '',
    this.outboundType = '',
    this.chain = const [],
    this.processName,
  });

  /// Parses a connection of the `sing_box/connections` channel.
  factory SingBoxConnection.fromMap(Map<dynamic, dynamic> map) {
    int readInt(String key) => (map[key] as num?)?.toInt() ?? 0;
    String readString(String key) => map[key] as String? ?? '';
    final closedAt = readInt('closedAt');
    final process = map['processName'] as String?;
    return SingBoxConnection(
      id: readString('id'),
      inbound: readString('inbound'),
      inboundType: readString('inboundType'),
      ipVersion: readInt('ipVersion'),
      network: readString('network'),
      source: readString('source'),
      destination: readString('destination'),
      domain: readString('domain'),
      protocol: readString('protocol'),
      user: readString('user'),
      fromOutbound: readString('fromOutbound'),
      createdAt: DateTime.fromMillisecondsSinceEpoch(readInt('createdAt')),
      closedAt: closedAt > 0
          ? DateTime.fromMillisecondsSinceEpoch(closedAt)
          : null,
      uploadSpeed: readInt('uplink'),
      downloadSpeed: readInt('downlink'),
      uploadTotal: readInt('uplinkTotal'),
      downloadTotal: readInt('downlinkTotal'),
      rule: readString('rule'),
      outbound: readString('outbound'),
      outboundType: readString('outboundType'),
      chain: (map['chain'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(growable: false),
      processName: process == null || process.isEmpty ? null : process,
    );
  }

  /// Unique connection id, used by `SingBox.closeConnection()`.
  final String id;

  /// Inbound tag that accepted the connection, e.g. `tun-in`.
  final String inbound;

  /// Inbound type, e.g. `tun`.
  final String inboundType;

  /// IP version of the connection (4 or 6).
  final int ipVersion;

  /// `tcp` or `udp`.
  final String network;

  /// Source address (`host:port`).
  final String source;

  /// Destination address (`host:port`).
  final String destination;

  /// Sniffed or resolved domain name, empty if unknown.
  final String domain;

  /// Sniffed protocol, e.g. `tls`, `http`, `quic`, `dns`.
  final String protocol;

  /// Authenticated inbound user, if any.
  final String user;

  /// Outbound that forwarded the connection back into routing, if any.
  final String fromOutbound;

  /// When the connection was opened.
  final DateTime createdAt;

  /// When the connection was closed, `null` while it is active.
  final DateTime? closedAt;

  /// Current upload speed in bytes per second.
  final int uploadSpeed;

  /// Current download speed in bytes per second.
  final int downloadSpeed;

  /// Bytes uploaded over the connection's lifetime.
  final int uploadTotal;

  /// Bytes downloaded over the connection's lifetime.
  final int downloadTotal;

  /// The routing rule that matched, e.g. `final` or `domain_suffix=...`.
  final String rule;

  /// Outbound tag that handles the connection.
  final String outbound;

  /// Outbound type.
  final String outboundType;

  /// Outbound chain from the top-level group to the actual server.
  final List<String> chain;

  /// Android package name or process path of the app that opened the
  /// connection, when the core could determine it.
  final String? processName;

  /// Whether the connection is still open.
  bool get isActive => closedAt == null;

  /// [domain] when known, otherwise [destination].
  String get displayDestination {
    if (domain.isEmpty) return destination;
    final port = destination.lastIndexOf(':');
    return port > 0 ? '$domain${destination.substring(port)}' : domain;
  }

  @override
  bool operator ==(Object other) =>
      other is SingBoxConnection &&
      other.id == id &&
      other.closedAt == closedAt &&
      other.uploadTotal == uploadTotal &&
      other.downloadTotal == downloadTotal;

  @override
  int get hashCode => Object.hash(id, closedAt, uploadTotal, downloadTotal);

  @override
  String toString() =>
      'SingBoxConnection($id, $network $displayDestination via $outbound)';
}
