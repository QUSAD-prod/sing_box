import '../models/connection_stats.dart';
import '../models/connection_status.dart';
import '../models/sing_box_notification.dart';
import 'sing_box_observer.dart';

/// A [SingBoxObserver] that forwards events to a
/// [Talker](https://pub.dev/packages/talker) instance.
///
/// `sing_box` does not depend on `talker`; the instance is used through
/// dynamic calls of its `info`, `warning`, `error` and `debug` methods, so
/// any object with the same methods works:
///
/// ```dart
/// import 'package:talker/talker.dart';
///
/// final talker = Talker();
/// SingBox.instance.setObserver(SingBoxTalkerObserver(talker));
/// ```
///
/// Traffic statistics are logged only when [logStats] is `true`, because
/// they arrive every second.
class SingBoxTalkerObserver extends SingBoxObserver {
  /// Creates an observer that logs to [talker].
  const SingBoxTalkerObserver(
    this.talker, {
    this.prefix = '[SingBox]',
    this.logStats = false,
  });

  /// The `Talker` instance (typed `dynamic` to avoid a hard dependency).
  final dynamic talker;

  /// Prefix added to every message.
  final String prefix;

  /// Whether [onConnectionStatsChanged] events are logged.
  final bool logStats;

  String _format(String message, Map<String, dynamic>? data) =>
      data != null && data.isNotEmpty
          ? '$prefix $message | $data'
          : '$prefix $message';

  void _call(void Function(dynamic talker) call) {
    final instance = talker;
    if (instance == null) return;
    try {
      call(instance);
    } catch (_) {
      // The object does not provide the method; logging must never throw.
    }
  }

  @override
  void info(String message, [Map<String, dynamic>? data]) =>
      _call((t) => t.info(_format(message, data)));

  @override
  void warning(String message, [Map<String, dynamic>? data]) =>
      _call((t) => t.warning(_format(message, data)));

  @override
  void error(String message, [Object? error, StackTrace? stackTrace]) =>
      _call((t) => t.error('$prefix $message', error, stackTrace));

  @override
  void debug(String message, [Map<String, dynamic>? data]) =>
      _call((t) => t.debug(_format(message, data)));

  @override
  void onConnect(String config) =>
      info('Connecting', {'configLength': config.length});

  @override
  void onDisconnect() => info('Disconnecting');

  @override
  void onStatusChanged(String status) => debug('Status: $status');

  @override
  void onConnectionStateChanged(SingBoxConnectionState state) {
    if (state.error != null) {
      warning('Tunnel stopped with an error', {'error': state.error});
    }
  }

  @override
  void onConnectionError(String error) =>
      this.error('Connection error: $error');

  @override
  void onConnectionStatsChanged(SingBoxConnectionStats stats) {
    if (!logStats) return;
    debug('Stats', {
      'up': '${stats.uploadSpeed} B/s',
      'down': '${stats.downloadSpeed} B/s',
      'upTotal': stats.uploadTotal,
      'downTotal': stats.downloadTotal,
      'duration': stats.duration.toString(),
    });
  }

  @override
  void onSettingsChanged(String key, dynamic value) =>
      debug('Setting changed', {'key': key, 'value': value});

  @override
  void onServerConfigAdded(String configId, String name) =>
      info('Server config added', {'id': configId, 'name': name});

  @override
  void onServerConfigRemoved(String configId) =>
      info('Server config removed', {'id': configId});

  @override
  void onActiveServerConfigChanged(String configId) =>
      info('Active server config changed', {'id': configId});

  @override
  void onNotification(SingBoxNotification notification) =>
      info('Notification: ${notification.title}', {'body': notification.body});
}
