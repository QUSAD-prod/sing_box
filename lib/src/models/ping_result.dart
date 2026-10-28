/// Result of a latency measurement.
///
/// Through a running tunnel sing-box measures latency with a URL test: an
/// HTTP request through the outbound (by default to
/// `https://www.gstatic.com/generate_204`), which reflects real proxy latency
/// including the handshake - unlike ICMP ping, which most proxy servers do
/// not even answer. `SingBox.pingServers` measures the TCP handshake time to
/// the server instead while the tunnel is stopped ([method]).
class SingBoxPingResult {
  /// Creates a ping result.
  const SingBoxPingResult({
    required this.ping,
    required this.success,
    this.errorMessage,
    this.address,
    this.tag,
    this.serverId,
    this.method = SingBoxPingMethod.urlTest,
  });

  /// Creates a failed result.
  const SingBoxPingResult.failure(
    String message, {
    this.address,
    this.tag,
    this.serverId,
    this.method = SingBoxPingMethod.urlTest,
  }) : ping = 0,
       success = false,
       errorMessage = message;

  /// Creates an object from a map (for deserialization).
  factory SingBoxPingResult.fromMap(Map<dynamic, dynamic> map) {
    return SingBoxPingResult(
      ping: (map['ping'] as num?)?.toInt() ?? 0,
      success: map['success'] as bool? ?? false,
      errorMessage: map['errorMessage'] as String?,
      address: map['address'] as String?,
      tag: map['tag'] as String?,
      serverId: map['serverId'] as String?,
      method: SingBoxPingMethod.fromName(map['method'] as String?),
    );
  }

  /// Latency in milliseconds (0 when [success] is `false`).
  final int ping;

  /// Whether the measurement succeeded.
  final bool success;

  /// Error description when [success] is `false`.
  final String? errorMessage;

  /// Server address of the measured outbound, when known.
  final String? address;

  /// Tag of the measured outbound, when it is part of the running
  /// configuration.
  final String? tag;

  /// Id of the measured server profile (`SingBox.pingServers`).
  final String? serverId;

  /// How the latency was measured.
  final SingBoxPingMethod method;

  /// [ping] as a [Duration].
  Duration get latency => Duration(milliseconds: ping);

  /// Returns a copy for the server profile [serverId].
  SingBoxPingResult forServer(String serverId) => SingBoxPingResult(
    ping: ping,
    success: success,
    errorMessage: errorMessage,
    address: address,
    tag: tag,
    serverId: serverId,
    method: method,
  );

  /// Converts the object to a map (for serialization).
  Map<String, dynamic> toMap() => {
    'ping': ping,
    'success': success,
    'errorMessage': errorMessage,
    'address': address,
    'tag': tag,
    'serverId': serverId,
    'method': method.name,
  };

  @override
  String toString() {
    final target = [
      if (serverId != null) 'server: $serverId',
      if (tag != null) 'tag: $tag',
      if (address != null) 'address: $address',
    ].join(', ');
    return success
        ? 'SingBoxPingResult(${ping}ms ${method.name}, $target)'
        : 'SingBoxPingResult(failed: $errorMessage, $target)';
  }
}

/// How a [SingBoxPingResult] was measured.
enum SingBoxPingMethod {
  /// HTTP request through the outbound of the running tunnel.
  urlTest,

  /// TCP handshake with the server, without the tunnel.
  tcp;

  /// Parses [name], defaulting to [urlTest].
  static SingBoxPingMethod fromName(String? name) =>
      name == tcp.name ? tcp : urlTest;
}
