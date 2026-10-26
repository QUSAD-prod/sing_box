/// Result of a latency measurement (URL test) through an outbound.
///
/// sing-box measures latency by performing an HTTP request through the
/// outbound (by default to `https://www.gstatic.com/generate_204`), which
/// reflects real proxy latency including the handshake - unlike ICMP ping,
/// which most proxy servers do not even answer.
class SingBoxPingResult {
  /// Creates a ping result.
  const SingBoxPingResult({
    required this.ping,
    required this.success,
    this.errorMessage,
    this.address,
    this.tag,
  });

  /// Creates a failed result.
  const SingBoxPingResult.failure(String message, {this.address, this.tag})
    : ping = 0,
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

  /// Tag of the measured outbound.
  final String? tag;

  /// [ping] as a [Duration].
  Duration get latency => Duration(milliseconds: ping);

  /// Converts the object to a map (for serialization).
  Map<String, dynamic> toMap() => {
    'ping': ping,
    'success': success,
    'errorMessage': errorMessage,
    'address': address,
    'tag': tag,
  };

  @override
  String toString() => success
      ? 'SingBoxPingResult(${ping}ms, tag: $tag, address: $address)'
      : 'SingBoxPingResult(failed: $errorMessage, tag: $tag)';
}
