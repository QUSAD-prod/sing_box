/// NAT mapping behaviour detected by a STUN test (RFC 4787).
enum SingBoxNatMapping {
  /// Unknown or not yet measured.
  unknown,

  /// The same external address is used for every destination ("full cone").
  endpointIndependent,

  /// The external address depends on the destination address.
  addressDependent,

  /// The external address depends on destination address and port
  /// ("symmetric NAT").
  addressAndPortDependent;

  /// Maps the numeric value used by libbox (0 = unknown, 1 is reserved,
  /// 2..4 = endpoint independent .. address and port dependent).
  static SingBoxNatMapping fromValue(int? value) {
    switch (value) {
      case 2:
        return endpointIndependent;
      case 3:
        return addressDependent;
      case 4:
        return addressAndPortDependent;
      default:
        return unknown;
    }
  }
}

/// NAT filtering behaviour detected by a STUN test (RFC 4787).
enum SingBoxNatFiltering {
  /// Unknown or not yet measured.
  unknown,

  /// Packets from any address are accepted.
  endpointIndependent,

  /// Only packets from previously contacted addresses are accepted.
  addressDependent,

  /// Only packets from previously contacted address:port pairs are accepted.
  addressAndPortDependent;

  /// Maps the numeric value used by libbox (0 = unknown, then 1..3).
  static SingBoxNatFiltering fromValue(int? value) {
    if (value == null || value < 0 || value >= values.length) return unknown;
    return values[value];
  }
}

/// Progress or result of a STUN (NAT type / UDP connectivity) test.
class SingBoxStunResult {
  /// Creates a STUN result.
  const SingBoxStunResult({
    this.externalAddress = '',
    this.latency,
    this.natMapping = SingBoxNatMapping.unknown,
    this.natFiltering = SingBoxNatFiltering.unknown,
    this.natTypeSupported = false,
    this.phase = 0,
    this.isFinal = false,
  });

  /// Parses an event of the `sing_box/stun` channel.
  factory SingBoxStunResult.fromMap(Map<dynamic, dynamic> map) {
    final latency = (map['latencyMs'] as num?)?.toInt() ?? 0;
    return SingBoxStunResult(
      externalAddress: map['externalAddr'] as String? ?? '',
      latency: latency > 0 ? Duration(milliseconds: latency) : null,
      natMapping: SingBoxNatMapping.fromValue(
        (map['natMapping'] as num?)?.toInt(),
      ),
      natFiltering: SingBoxNatFiltering.fromValue(
        (map['natFiltering'] as num?)?.toInt(),
      ),
      natTypeSupported: map['natTypeSupported'] as bool? ?? false,
      phase: (map['phase'] as num?)?.toInt() ?? 0,
      isFinal: map['type'] == 'result',
    );
  }

  /// Public address and port as seen by the STUN server (i.e. the proxy's
  /// egress address when tested through the tunnel).
  final String externalAddress;

  /// Round-trip time to the STUN server.
  final Duration? latency;

  /// Detected NAT mapping behaviour.
  final SingBoxNatMapping natMapping;

  /// Detected NAT filtering behaviour.
  final SingBoxNatFiltering natFiltering;

  /// Whether the server supports NAT type detection (RFC 5780).
  final bool natTypeSupported;

  /// libbox phase number (0 binding, 1 mapping, 2 filtering, 3 done).
  final int phase;

  /// Whether this is the final result.
  final bool isFinal;

  @override
  String toString() =>
      'SingBoxStunResult($externalAddress, latency: '
      '${latency?.inMilliseconds ?? '-'} ms, mapping: ${natMapping.name}, '
      'filtering: ${natFiltering.name})';
}
