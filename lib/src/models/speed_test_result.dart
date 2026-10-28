import 'network_quality.dart';

/// Simplified result of `SingBox.testSpeed()`.
///
/// For progress updates and responsiveness metrics use
/// `SingBox.runNetworkQualityTest()`, which this class summarizes.
class SingBoxSpeedTestResult {
  /// Creates a speed test result.
  const SingBoxSpeedTestResult({
    required this.downloadSpeed,
    required this.uploadSpeed,
    required this.success,
    this.errorMessage,
    this.latency,
    this.quality,
  });

  /// Creates a failed result.
  const SingBoxSpeedTestResult.failure(String message)
    : downloadSpeed = 0,
      uploadSpeed = 0,
      success = false,
      errorMessage = message,
      latency = null,
      quality = null;

  /// Builds a result from the final network quality measurement.
  factory SingBoxSpeedTestResult.fromNetworkQuality(
    SingBoxNetworkQuality quality,
  ) {
    return SingBoxSpeedTestResult(
      downloadSpeed: quality.downloadCapacity ~/ 8,
      uploadSpeed: quality.uploadCapacity ~/ 8,
      success: true,
      latency: quality.idleLatency,
      quality: quality,
    );
  }

  /// Creates an object from a map (for deserialization).
  factory SingBoxSpeedTestResult.fromMap(Map<dynamic, dynamic> map) {
    final latency = (map['latencyMs'] as num?)?.toInt();
    return SingBoxSpeedTestResult(
      downloadSpeed: (map['downloadSpeed'] as num?)?.toInt() ?? 0,
      uploadSpeed: (map['uploadSpeed'] as num?)?.toInt() ?? 0,
      success: map['success'] as bool? ?? false,
      errorMessage: map['errorMessage'] as String?,
      latency: latency == null ? null : Duration(milliseconds: latency),
    );
  }

  /// Download speed in bytes per second.
  final int downloadSpeed;

  /// Upload speed in bytes per second.
  final int uploadSpeed;

  /// Whether the test completed successfully.
  final bool success;

  /// Error description when [success] is `false`.
  final String? errorMessage;

  /// Idle latency measured during the test.
  final Duration? latency;

  /// The full measurement, when available.
  final SingBoxNetworkQuality? quality;

  /// Download speed in megabits per second.
  double get downloadMbps => downloadSpeed * 8 / 1e6;

  /// Upload speed in megabits per second.
  double get uploadMbps => uploadSpeed * 8 / 1e6;

  /// Converts the object to a map (for serialization).
  Map<String, dynamic> toMap() => {
    'downloadSpeed': downloadSpeed,
    'uploadSpeed': uploadSpeed,
    'success': success,
    'errorMessage': errorMessage,
    'latencyMs': latency?.inMilliseconds,
  };

  @override
  String toString() =>
      success
          ? 'SingBoxSpeedTestResult(down: ${downloadMbps.toStringAsFixed(1)} '
              'Mbps, up: ${uploadMbps.toStringAsFixed(1)} Mbps)'
          : 'SingBoxSpeedTestResult(failed: $errorMessage)';
}
