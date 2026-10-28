/// Severity of a sing-box log message.
///
/// The numeric [value]s match sing-box's internal levels.
enum SingBoxLogLevel {
  /// Panic (0).
  panic(0),

  /// Fatal (1).
  fatal(1),

  /// Error (2).
  error(2),

  /// Warning (3).
  warn(3),

  /// Informational (4).
  info(4),

  /// Debug (5).
  debug(5),

  /// Trace (6).
  trace(6);

  const SingBoxLogLevel(this.value);

  /// Numeric level used by sing-box.
  final int value;

  /// Returns the level for a sing-box numeric [value]; unknown values map to
  /// [info].
  static SingBoxLogLevel fromValue(int? value) {
    for (final level in values) {
      if (level.value == value) return level;
    }
    return info;
  }

  /// Whether this level is at least as severe as [other].
  bool isAtLeast(SingBoxLogLevel other) => value <= other.value;
}

/// A single log line produced by the sing-box core.
class SingBoxLogEntry {
  /// Creates a log entry.
  const SingBoxLogEntry({
    required this.level,
    required this.message,
    required this.receivedAt,
  });

  /// Parses an entry of the `sing_box/logs` channel.
  factory SingBoxLogEntry.fromMap(Map<dynamic, dynamic> map, {DateTime? at}) {
    return SingBoxLogEntry(
      level: SingBoxLogLevel.fromValue((map['level'] as num?)?.toInt()),
      message: map['message'] as String? ?? '',
      receivedAt: at ?? DateTime.now(),
    );
  }

  /// Severity of the message.
  final SingBoxLogLevel level;

  /// The log message. sing-box messages may contain ANSI color codes; use
  /// [plainMessage] to get them stripped.
  final String message;

  /// When the app received the message (sing-box does not send timestamps).
  final DateTime receivedAt;

  static final _ansi = RegExp(r'\x1B\[[0-9;]*m');

  /// [message] without ANSI escape sequences.
  String get plainMessage => message.replaceAll(_ansi, '');

  @override
  bool operator ==(Object other) =>
      other is SingBoxLogEntry &&
      other.level == level &&
      other.message == message &&
      other.receivedAt == receivedAt;

  @override
  int get hashCode => Object.hash(level, message, receivedAt);

  @override
  String toString() => '[${level.name.toUpperCase()}] $plainMessage';
}

/// An event of the log stream, see `SingBox.watchLogEvents()`.
sealed class SingBoxLogEvent {
  const SingBoxLogEvent();

  /// Parses an event of the `sing_box/logs` channel. Returns `null` for
  /// unknown event types.
  static SingBoxLogEvent? fromMap(Map<dynamic, dynamic> map) {
    switch (map['type']) {
      case 'logs':
        final now = DateTime.now();
        final entries = (map['entries'] as List<dynamic>? ?? const [])
            .whereType<Map<dynamic, dynamic>>()
            .map((e) => SingBoxLogEntry.fromMap(e, at: now))
            .toList(growable: false);
        return SingBoxLogBatch(entries, reset: map['reset'] as bool? ?? false);
      case 'defaultLevel':
        return SingBoxLogDefaultLevel(
          SingBoxLogLevel.fromValue((map['level'] as num?)?.toInt()),
        );
      case 'clear':
        return const SingBoxLogCleared();
    }
    return null;
  }
}

/// New log entries. When [reset] is `true` the previously received entries
/// are obsolete (the core restarted) and should be discarded first.
class SingBoxLogBatch extends SingBoxLogEvent {
  /// Creates a batch.
  const SingBoxLogBatch(this.entries, {this.reset = false});

  /// The new entries, oldest first.
  final List<SingBoxLogEntry> entries;

  /// Whether earlier entries should be discarded.
  final bool reset;
}

/// The log level configured in the running sing-box config.
class SingBoxLogDefaultLevel extends SingBoxLogEvent {
  /// Creates the event.
  const SingBoxLogDefaultLevel(this.level);

  /// The configured level.
  final SingBoxLogLevel level;
}

/// The log buffer was cleared (for example via `SingBox.clearLogs()`).
class SingBoxLogCleared extends SingBoxLogEvent {
  /// Creates the event.
  const SingBoxLogCleared();
}
