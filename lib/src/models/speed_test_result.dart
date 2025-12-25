/// Connection speed test result
class SingBoxSpeedTestResult {
  /// Download speed in bytes per second
  final int downloadSpeed;

  /// Upload speed in bytes per second
  final int uploadSpeed;

  /// Whether test was successful
  final bool success;

  /// Error message if test failed
  final String? errorMessage;

  const SingBoxSpeedTestResult({
    required this.downloadSpeed,
    required this.uploadSpeed,
    required this.success,
    this.errorMessage,
  });

  /// Creates an object from Map (for deserialization from native platform)
  factory SingBoxSpeedTestResult.fromMap(Map<dynamic, dynamic> map) {
    return SingBoxSpeedTestResult(
      downloadSpeed: map['downloadSpeed'] as int? ?? 0,
      uploadSpeed: map['uploadSpeed'] as int? ?? 0,
      success: map['success'] as bool? ?? false,
      errorMessage: map['errorMessage'] as String?,
    );
  }

  /// Converts object to Map (for serialization to native platform)
  Map<String, dynamic> toMap() {
    return {
      'downloadSpeed': downloadSpeed,
      'uploadSpeed': uploadSpeed,
      'success': success,
      'errorMessage': errorMessage,
    };
  }

  @override
  String toString() {
    if (success) {
      return 'SingBoxSpeedTestResult(download: ${downloadSpeed}B/s, upload: ${uploadSpeed}B/s)';
    } else {
      return 'SingBoxSpeedTestResult(failed: $errorMessage)';
    }
  }
}
