/// Connection statistics
class SingBoxConnectionStats {
  /// Current download speed in bytes per second
  final int downloadSpeed;

  /// Current upload speed in bytes per second
  final int uploadSpeed;

  /// Total bytes sent
  final int bytesSent;

  /// Total bytes received
  final int bytesReceived;

  /// Current ping in milliseconds
  final int? ping;

  /// Connection duration in milliseconds since connection start
  /// Available in statistics listener via watchConnectionStats()
  final int connectionDuration;

  const SingBoxConnectionStats({
    required this.downloadSpeed,
    required this.uploadSpeed,
    required this.bytesSent,
    required this.bytesReceived,
    this.ping,
    required this.connectionDuration,
  });

  /// Creates an object from Map (for deserialization from native platform)
  factory SingBoxConnectionStats.fromMap(Map<dynamic, dynamic> map) {
    return SingBoxConnectionStats(
      downloadSpeed: map['downloadSpeed'] as int? ?? 0,
      uploadSpeed: map['uploadSpeed'] as int? ?? 0,
      bytesSent: map['bytesSent'] as int? ?? 0,
      bytesReceived: map['bytesReceived'] as int? ?? 0,
      ping: map['ping'] as int?,
      connectionDuration: map['connectionDuration'] as int? ?? 0,
    );
  }

  /// Converts object to Map (for serialization to native platform)
  Map<String, dynamic> toMap() {
    return {
      'downloadSpeed': downloadSpeed,
      'uploadSpeed': uploadSpeed,
      'bytesSent': bytesSent,
      'bytesReceived': bytesReceived,
      'ping': ping,
      'connectionDuration': connectionDuration,
    };
  }

  @override
  String toString() {
    return 'SingBoxConnectionStats(downloadSpeed: $downloadSpeed, uploadSpeed: $uploadSpeed, '
        'bytesSent: $bytesSent, bytesReceived: $bytesReceived, '
        'ping: $ping, connectionDuration: $connectionDuration)';
  }
}
