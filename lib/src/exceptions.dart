import 'package:flutter/services.dart';

/// Base class of every error thrown by the `sing_box` plugin.
///
/// Native failures arrive as [PlatformException]s and are converted into one
/// of the subclasses below by [SingBoxException.fromPlatformException], so
/// callers can either catch [SingBoxException] or a specific subtype:
///
/// ```dart
/// try {
///   await SingBox.instance.connect(config);
/// } on SingBoxPermissionException {
///   // Ask the user to grant the VPN permission.
/// } on SingBoxConfigException catch (e) {
///   print('sing-box rejected the config: ${e.message}');
/// } on SingBoxException catch (e) {
///   print('Failed: $e');
/// }
/// ```
class SingBoxException implements Exception {
  /// Creates an exception with an error [code] and a human readable
  /// [message].
  const SingBoxException(this.code, this.message, {this.details});

  /// Converts a [PlatformException] produced by the native side into the most
  /// specific [SingBoxException] subtype.
  factory SingBoxException.fromPlatformException(PlatformException e) {
    final message = e.message ?? e.code;
    switch (e.code) {
      case SingBoxErrorCode.invalidConfig:
        return SingBoxConfigException(message, details: e.details);
      case SingBoxErrorCode.permissionDenied:
        return SingBoxPermissionException(message, details: e.details);
      case SingBoxErrorCode.serviceNotRunning:
        return SingBoxServiceNotRunningException(message, details: e.details);
      case SingBoxErrorCode.unsupported:
        return SingBoxUnsupportedException(message, details: e.details);
      case SingBoxErrorCode.notInitialized:
        return SingBoxNotInitializedException(message);
      default:
        return SingBoxException(e.code, message, details: e.details);
    }
  }

  /// Machine readable error code, one of the [SingBoxErrorCode] constants.
  final String code;

  /// Human readable description, usually the error reported by sing-box or
  /// the operating system.
  final String message;

  /// Optional platform specific details.
  final Object? details;

  @override
  String toString() => 'SingBoxException($code): $message';
}

/// The configuration was rejected by sing-box.
///
/// [message] contains the exact error reported by the sing-box core, for
/// example `decode config at outbounds[0]: unknown field "uuidd"`.
class SingBoxConfigException extends SingBoxException {
  /// Creates a configuration error.
  const SingBoxConfigException(String message, {Object? details})
      : super(SingBoxErrorCode.invalidConfig, message, details: details);

  @override
  String toString() => 'SingBoxConfigException: $message';
}

/// The VPN permission (Android) or VPN profile (iOS) has not been granted.
///
/// Call `SingBox.instance.requestVpnPermission()` and retry.
class SingBoxPermissionException extends SingBoxException {
  /// Creates a permission error.
  const SingBoxPermissionException(String message, {Object? details})
      : super(SingBoxErrorCode.permissionDenied, message, details: details);

  @override
  String toString() => 'SingBoxPermissionException: $message';
}

/// The operation needs a running VPN service, but it is stopped.
class SingBoxServiceNotRunningException extends SingBoxException {
  /// Creates a "service not running" error.
  const SingBoxServiceNotRunningException(String message, {Object? details})
      : super(SingBoxErrorCode.serviceNotRunning, message, details: details);

  @override
  String toString() => 'SingBoxServiceNotRunningException: $message';
}

/// The feature is not available on the current platform or OS version.
class SingBoxUnsupportedException extends SingBoxException {
  /// Creates an "unsupported" error.
  const SingBoxUnsupportedException(String message, {Object? details})
      : super(SingBoxErrorCode.unsupported, message, details: details);

  @override
  String toString() => 'SingBoxUnsupportedException: $message';
}

/// A method was called before `SingBox.instance.initialize()` completed.
class SingBoxNotInitializedException extends SingBoxException {
  /// Creates a "not initialized" error.
  const SingBoxNotInitializedException([
    String message =
        'SingBox is not initialized. Call SingBox.instance.initialize() first.',
  ]) : super(SingBoxErrorCode.notInitialized, message);

  @override
  String toString() => 'SingBoxNotInitializedException: $message';
}

/// Error codes shared by the Dart and native sides.
///
/// See `doc/platform_channel.md` for the full contract.
abstract final class SingBoxErrorCode {
  /// `initialize` has not been called yet.
  static const notInitialized = 'NOT_INITIALIZED';

  /// A required argument is missing or malformed.
  static const invalidArgument = 'INVALID_ARGUMENT';

  /// sing-box rejected the configuration.
  static const invalidConfig = 'INVALID_CONFIG';

  /// The VPN permission or profile is missing.
  static const permissionDenied = 'PERMISSION_DENIED';

  /// The VPN service is not running.
  static const serviceNotRunning = 'SERVICE_NOT_RUNNING';

  /// The tunnel could not be started.
  static const startFailed = 'START_FAILED';

  /// A libbox command failed.
  static const commandFailed = 'COMMAND_FAILED';

  /// Not supported on this platform.
  static const unsupported = 'UNSUPPORTED';

  /// Android only: an `Activity` is required but none is attached.
  static const noActivity = 'NO_ACTIVITY';

  /// Any other failure.
  static const internal = 'INTERNAL';
}
