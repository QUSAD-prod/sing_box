/// Phase of a network quality (speed) test.
enum SingBoxNetworkQualityPhase {
  /// Measuring idle latency.
  idle,

  /// Measuring download capacity and responsiveness.
  download,

  /// Measuring upload capacity and responsiveness.
  upload,

  /// The test finished.
  done;

  /// Maps the numeric phase used by libbox.
  static SingBoxNetworkQualityPhase fromValue(int? value) {
    if (value == null || value < 0 || value >= values.length) return idle;
    return values[value];
  }
}

/// Confidence of a network quality measurement.
enum SingBoxMeasurementAccuracy {
  /// Few samples, the value may still change a lot.
  low,

  /// Reasonable confidence.
  medium,

  /// High confidence.
  high;

  /// Maps the numeric accuracy used by libbox.
  static SingBoxMeasurementAccuracy fromValue(int? value) {
    if (value == null || value < 0 || value >= values.length) return low;
    return values[value];
  }
}

/// Progress or final values of a network quality test.
///
/// The test follows the IETF *Responsiveness under Working Conditions*
/// methodology (the same as Apple's `networkQuality` tool) and measures
/// through the proxy, so it reflects the speed the user actually gets.
class SingBoxNetworkQuality {
  /// Creates a measurement.
  const SingBoxNetworkQuality({
    this.phase = SingBoxNetworkQualityPhase.done,
    this.downloadCapacity = 0,
    this.uploadCapacity = 0,
    this.downloadRpm = 0,
    this.uploadRpm = 0,
    this.idleLatency,
    this.elapsed = Duration.zero,
    this.downloadCapacityAccuracy = SingBoxMeasurementAccuracy.low,
    this.uploadCapacityAccuracy = SingBoxMeasurementAccuracy.low,
    this.downloadRpmAccuracy = SingBoxMeasurementAccuracy.low,
    this.uploadRpmAccuracy = SingBoxMeasurementAccuracy.low,
    this.isFinal = false,
  });

  /// Parses an event of the `sing_box/network_quality` channel.
  factory SingBoxNetworkQuality.fromMap(Map<dynamic, dynamic> map) {
    int read(String key) => (map[key] as num?)?.toInt() ?? 0;
    final isFinal = map['type'] == 'result';
    final latency = read('idleLatencyMs');
    return SingBoxNetworkQuality(
      phase:
          isFinal
              ? SingBoxNetworkQualityPhase.done
              : SingBoxNetworkQualityPhase.fromValue(read('phase')),
      downloadCapacity: read('downloadCapacity'),
      uploadCapacity: read('uploadCapacity'),
      downloadRpm: read('downloadRPM'),
      uploadRpm: read('uploadRPM'),
      idleLatency: latency > 0 ? Duration(milliseconds: latency) : null,
      elapsed: Duration(milliseconds: read('elapsedMs')),
      downloadCapacityAccuracy: SingBoxMeasurementAccuracy.fromValue(
        read('downloadCapacityAccuracy'),
      ),
      uploadCapacityAccuracy: SingBoxMeasurementAccuracy.fromValue(
        read('uploadCapacityAccuracy'),
      ),
      downloadRpmAccuracy: SingBoxMeasurementAccuracy.fromValue(
        read('downloadRPMAccuracy'),
      ),
      uploadRpmAccuracy: SingBoxMeasurementAccuracy.fromValue(
        read('uploadRPMAccuracy'),
      ),
      isFinal: isFinal,
    );
  }

  /// Current phase.
  final SingBoxNetworkQualityPhase phase;

  /// Download capacity in bits per second.
  final int downloadCapacity;

  /// Upload capacity in bits per second.
  final int uploadCapacity;

  /// Download responsiveness in round-trips per minute (higher is better).
  final int downloadRpm;

  /// Upload responsiveness in round-trips per minute (higher is better).
  final int uploadRpm;

  /// Latency of an idle connection, `null` until measured.
  final Duration? idleLatency;

  /// Time since the test started (progress events only).
  final Duration elapsed;

  /// Accuracy of [downloadCapacity].
  final SingBoxMeasurementAccuracy downloadCapacityAccuracy;

  /// Accuracy of [uploadCapacity].
  final SingBoxMeasurementAccuracy uploadCapacityAccuracy;

  /// Accuracy of [downloadRpm].
  final SingBoxMeasurementAccuracy downloadRpmAccuracy;

  /// Accuracy of [uploadRpm].
  final SingBoxMeasurementAccuracy uploadRpmAccuracy;

  /// Whether this is the final result.
  final bool isFinal;

  /// Download capacity in megabits per second.
  double get downloadMbps => downloadCapacity / 1e6;

  /// Upload capacity in megabits per second.
  double get uploadMbps => uploadCapacity / 1e6;

  @override
  String toString() =>
      'SingBoxNetworkQuality(${phase.name}, '
      'down: ${downloadMbps.toStringAsFixed(1)} Mbps, '
      'up: ${uploadMbps.toStringAsFixed(1)} Mbps, '
      'latency: ${idleLatency?.inMilliseconds ?? '-'} ms, '
      'rpm: $downloadRpm/$uploadRpm${isFinal ? ', final' : ''})';
}
