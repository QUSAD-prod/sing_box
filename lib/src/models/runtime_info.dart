import 'connection_status.dart';

/// Information returned by the native side after initialization.
class SingBoxRuntimeInfo {
  /// Creates runtime information.
  const SingBoxRuntimeInfo({
    required this.singBoxVersion,
    this.status = SingBoxConnectionStatus.disconnected,
    this.workingDirectory,
  });

  /// Parses the result of the `initialize` method.
  factory SingBoxRuntimeInfo.fromMap(Map<dynamic, dynamic> map) {
    return SingBoxRuntimeInfo(
      singBoxVersion: map['singBoxVersion'] as String? ?? '',
      status: SingBoxConnectionStatus.fromString(map['status'] as String?),
      workingDirectory: map['workingDirectory'] as String?,
    );
  }

  /// Version of the bundled sing-box core, e.g. `1.14.4`.
  final String singBoxVersion;

  /// Tunnel status at initialization time.
  final SingBoxConnectionStatus status;

  /// Absolute path of the sing-box working directory (cache file, rule-sets).
  final String? workingDirectory;

  @override
  String toString() =>
      'SingBoxRuntimeInfo(singBoxVersion: $singBoxVersion, '
      'status: ${status.name}, workingDirectory: $workingDirectory)';
}
