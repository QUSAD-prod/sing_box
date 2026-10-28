/// State of the VPN tunnel.
enum SingBoxConnectionStatus {
  /// The tunnel is not running.
  disconnected,

  /// The tunnel is starting (or reconnecting after a network change on iOS).
  connecting,

  /// The tunnel is running and traffic is routed through sing-box.
  connected,

  /// The tunnel is shutting down.
  disconnecting;

  /// Whether the tunnel is running or about to run.
  bool get isActive => this == connecting || this == connected;

  /// Whether the status is a transition (connecting or disconnecting).
  bool get isTransitioning => this == connecting || this == disconnecting;

  /// Parses the wire value used by the native side.
  ///
  /// Unknown values map to [disconnected].
  static SingBoxConnectionStatus fromString(String? value) {
    switch (value) {
      case 'connecting':
      case 'reasserting':
        return connecting;
      case 'connected':
        return connected;
      case 'disconnecting':
        return disconnecting;
      default:
        return disconnected;
    }
  }
}

/// Snapshot of the tunnel state including timing and the last error.
class SingBoxConnectionState {
  /// Creates a connection state.
  const SingBoxConnectionState({
    required this.status,
    this.startedAt,
    this.error,
  });

  /// The initial state before the native side reported anything.
  static const initial = SingBoxConnectionState(
    status: SingBoxConnectionStatus.disconnected,
  );

  /// Parses an event of the `sing_box/status` channel.
  factory SingBoxConnectionState.fromMap(Map<dynamic, dynamic> map) {
    final startedAt = map['startedAt'];
    final error = map['error'];
    return SingBoxConnectionState(
      status: SingBoxConnectionStatus.fromString(map['status'] as String?),
      startedAt:
          startedAt is int && startedAt > 0
              ? DateTime.fromMillisecondsSinceEpoch(startedAt)
              : null,
      error: error is String && error.isNotEmpty ? error : null,
    );
  }

  /// Current status.
  final SingBoxConnectionStatus status;

  /// When the current session started, `null` when not connected.
  final DateTime? startedAt;

  /// The error that stopped the last session, if it ended because of a
  /// failure. Cleared by the next successful start.
  final String? error;

  /// How long the tunnel has been connected, [Duration.zero] when it is not.
  Duration get duration {
    final start = startedAt;
    if (start == null || status != SingBoxConnectionStatus.connected) {
      return Duration.zero;
    }
    final elapsed = DateTime.now().difference(start);
    return elapsed.isNegative ? Duration.zero : elapsed;
  }

  /// Serializes the state using the wire format.
  Map<String, dynamic> toMap() => {
    'status': status.name,
    'startedAt': startedAt?.millisecondsSinceEpoch,
    'error': error,
  };

  @override
  bool operator ==(Object other) =>
      other is SingBoxConnectionState &&
      other.status == status &&
      other.startedAt == startedAt &&
      other.error == error;

  @override
  int get hashCode => Object.hash(status, startedAt, error);

  @override
  String toString() =>
      'SingBoxConnectionState(status: ${status.name}, startedAt: $startedAt, '
      'error: $error)';
}
