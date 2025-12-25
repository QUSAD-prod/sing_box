import 'sing_box_observer.dart';
import '../models/connection_stats.dart';

/// Observer for Talker integration
/// 
/// To use, add talker dependency to pubspec.yaml:
/// ```yaml
/// dependencies:
///   talker: ^3.0.0
/// ```
/// 
/// Usage example:
/// ```dart
/// import 'package:talker/talker.dart';
/// import 'package:sing_box/sing_box.dart';
/// 
/// final talker = Talker();
/// final observer = SingBoxTalkerObserver(talker);
/// SingBox.instance.setObserver(observer);
/// ```
class SingBoxTalkerObserver implements SingBoxObserver {
  /// Talker instance for logging
  /// Uses dynamic for compatibility without required dependency
  final dynamic talker;

  /// Prefix for all logs
  final String prefix;

  SingBoxTalkerObserver(this.talker, {this.prefix = '[SingBox]'});

  void _log(String level, String message, [Map<String, dynamic>? data]) {
    if (talker == null) return;
    
    final fullMessage = data != null && data.isNotEmpty
        ? '$prefix $message | Data: $data'
        : '$prefix $message';
    
    try {
      // Use dynamic call for compatibility
      final method = (talker as dynamic)[level];
      if (method != null && method is Function) {
        Function.apply(method, [fullMessage], {});
      }
    } catch (e) {
      // If talker is unavailable, ignore error
    }
  }

  @override
  void info(String message, [Map<String, dynamic>? data]) {
    _log('info', message, data);
  }

  @override
  void warning(String message, [Map<String, dynamic>? data]) {
    _log('warning', message, data);
  }

  @override
  void error(String message, [Object? error, StackTrace? stackTrace]) {
    if (talker == null) return;
    try {
      final fullMessage = '$prefix $message';
      final errorMethod = (talker as dynamic)['error'];
      if (errorMethod != null && errorMethod is Function) {
        if (error != null && stackTrace != null) {
          Function.apply(errorMethod, [fullMessage, error, stackTrace], {});
        } else if (error != null) {
          Function.apply(errorMethod, [fullMessage, error], {});
        } else {
          Function.apply(errorMethod, [fullMessage], {});
        }
      }
    } catch (e) {
      // If talker is unavailable, ignore error
    }
  }

  @override
  void debug(String message, [Map<String, dynamic>? data]) {
    _log('debug', message, data);
  }

  @override
  void onConnect(String config) {
    info('Connecting to VPN', {'config': config});
  }

  @override
  void onDisconnect() {
    info('Disconnecting from VPN');
  }

  @override
  void onStatusChanged(String status) {
    debug('Connection status changed', {'status': status});
  }

  @override
  void onConnectionError(String error) {
    this.error('Connection error: $error');
  }

  @override
  void onConnectionStatsChanged(SingBoxConnectionStats stats) {
    debug('Connection stats updated', {
      'downloadSpeed': '${stats.downloadSpeed} B/s',
      'uploadSpeed': '${stats.uploadSpeed} B/s',
      'bytesSent': stats.bytesSent,
      'bytesReceived': stats.bytesReceived,
      'ping': stats.ping != null ? '${stats.ping} ms' : null,
      'connectionDuration': '${stats.connectionDuration} ms',
    });
  }

  @override
  void onSettingsChanged(String key, dynamic value) {
    debug('Settings changed', {'key': key, 'value': value});
  }

  @override
  void onServerConfigAdded(String configId, String name) {
    info('Server config added', {'id': configId, 'name': name});
  }

  @override
  void onServerConfigRemoved(String configId) {
    info('Server config removed', {'id': configId});
  }

  @override
  void onActiveServerConfigChanged(String configId) {
    info('Active server config changed', {'id': configId});
  }
}
