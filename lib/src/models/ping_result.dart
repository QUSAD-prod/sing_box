/// Result of a latency measurement; [method] tells how it was measured.
///
/// The proxy methods ([SingBoxPingMethod.proxyHead], [SingBoxPingMethod.proxyGet])
/// send an HTTP request through the server to [url] (by default
/// `https://www.gstatic.com/generate_204`) and measure the time until the
/// response headers arrive: the real latency of the proxy, including its
/// handshake. [SingBoxPingMethod.tcp] and [SingBoxPingMethod.icmp] only
/// measure the network path to the server.
class SingBoxPingResult {
  /// Creates a ping result.
  const SingBoxPingResult({
    required this.ping,
    required this.success,
    this.errorMessage,
    this.address,
    this.tag,
    this.serverId,
    this.method = SingBoxPingMethod.proxyHead,
    this.url,
    this.statusCode,
  });

  /// Creates a failed result.
  const SingBoxPingResult.failure(
    String message, {
    this.address,
    this.tag,
    this.serverId,
    this.method = SingBoxPingMethod.proxyHead,
    this.url,
  }) : ping = 0,
       success = false,
       errorMessage = message,
       statusCode = null;

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
      url: map['url'] as String?,
      statusCode: (map['statusCode'] as num?)?.toInt(),
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

  /// The requested URL of a proxy measurement.
  final String? url;

  /// HTTP status code of a proxy measurement (any status counts as
  /// success: the server answered through the proxy).
  final int? statusCode;

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
    url: url,
    statusCode: statusCode,
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
    'url': url,
    'statusCode': statusCode,
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

/// How a [SingBoxPingResult] is measured.
///
/// | Method | Measures | Works for |
/// |--------|----------|-----------|
/// | [proxyHead] | `HEAD` request through the proxy, time to the response headers (like sing-box URL tests) | every protocol, also UDP based ones |
/// | [proxyGet] | `GET` request through the proxy, time to the response headers | every protocol; some sites answer `HEAD` differently |
/// | [tcp] | TCP handshake with the server | TCP based protocols (not Hysteria, TUIC, WireGuard, QUIC) |
/// | [icmp] | ICMP echo (system ping) to the server | servers that answer ping (many do not) |
///
/// [tcp] and [icmp] bypass the tunnel. The proxy methods use the running
/// tunnel when it is connected and a temporary core without TUN otherwise.
enum SingBoxPingMethod {
  /// `HEAD` request through the proxy (the default).
  proxyHead,

  /// `GET` request through the proxy.
  proxyGet,

  /// TCP handshake with the server, outside the tunnel.
  tcp,

  /// ICMP echo to the server, outside the tunnel.
  icmp,

  /// Former name of [proxyHead].
  @Deprecated('Use proxyHead')
  urlTest;

  /// Whether the latency is measured with an HTTP request through the
  /// proxy.
  // ignore: deprecated_member_use_from_same_package
  bool get isProxy => this == proxyHead || this == proxyGet || this == urlTest;

  /// Parses [name], defaulting to [proxyHead] (also for the former
  /// `urlTest`).
  static SingBoxPingMethod fromName(String? name) => switch (name) {
    'proxyGet' => proxyGet,
    'tcp' => tcp,
    'icmp' => icmp,
    _ => proxyHead,
  };
}
