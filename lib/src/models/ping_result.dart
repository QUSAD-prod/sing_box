/// Ping measurement result
class SingBoxPingResult {
  /// Ping in milliseconds
  final int ping;

  /// Whether ping was successful
  final bool success;

  /// Error message if ping failed
  final String? errorMessage;

  /// Address to which ping was measured
  final String? address;

  const SingBoxPingResult({
    required this.ping,
    required this.success,
    this.errorMessage,
    this.address,
  });

  /// Creates an object from Map (for deserialization from native platform)
  factory SingBoxPingResult.fromMap(Map<dynamic, dynamic> map) {
    return SingBoxPingResult(
      ping: map['ping'] as int? ?? 0,
      success: map['success'] as bool? ?? false,
      errorMessage: map['errorMessage'] as String?,
      address: map['address'] as String?,
    );
  }

  /// Converts object to Map (for serialization to native platform)
  Map<String, dynamic> toMap() {
    return {
      'ping': ping,
      'success': success,
      'errorMessage': errorMessage,
      'address': address,
    };
  }

  @override
  String toString() {
    if (success) {
      return 'SingBoxPingResult(ping: ${ping}ms, address: $address)';
    } else {
      return 'SingBoxPingResult(failed: $errorMessage, address: $address)';
    }
  }
}
