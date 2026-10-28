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
      case SingBoxErrorCode.startFailed:
        return SingBoxStartException(message, details: e.details);
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
  const SingBoxConfigException(String message, {super.details})
    : super(SingBoxErrorCode.invalidConfig, message);

  @override
  String toString() => 'SingBoxConfigException: $message';
}

/// The VPN permission (Android) or VPN profile (iOS) has not been granted.
///
/// Call `SingBox.instance.requestVpnPermission()` and retry.
class SingBoxPermissionException extends SingBoxException {
  /// Creates a permission error.
  const SingBoxPermissionException(String message, {super.details})
    : super(SingBoxErrorCode.permissionDenied, message);

  @override
  String toString() => 'SingBoxPermissionException: $message';
}

/// The tunnel could not be started, or it stopped before it connected.
///
/// [message] contains the exact error reported by the sing-box core or the
/// operating system, for example
/// `start service: initialize outbound[0]: missing uuid`.
class SingBoxStartException extends SingBoxException {
  /// Creates a start error.
  const SingBoxStartException(String message, {super.details})
    : super(SingBoxErrorCode.startFailed, message);

  @override
  String toString() => 'SingBoxStartException: $message';
}

/// The tunnel did not reach the expected state in time.
///
/// Thrown by `SingBox.connect` when the tunnel is still connecting after the
/// timeout. The tunnel is left as it is: follow
/// `SingBox.watchConnectionStatus` or call `SingBox.disconnect`.
class SingBoxTimeoutException extends SingBoxException {
  /// Creates a timeout error.
  const SingBoxTimeoutException(String message, {super.details})
    : super(SingBoxErrorCode.timeout, message);

  @override
  String toString() => 'SingBoxTimeoutException: $message';
}

/// The operation was superseded, for example a `SingBox.connect` that was
/// still waiting for the tunnel when `SingBox.disconnect` or another
/// `SingBox.connect` was called.
class SingBoxCancelledException extends SingBoxException {
  /// Creates a cancellation error.
  const SingBoxCancelledException(String message, {super.details})
    : super(SingBoxErrorCode.cancelled, message);

  @override
  String toString() => 'SingBoxCancelledException: $message';
}

/// The operation needs a running VPN service, but it is stopped.
class SingBoxServiceNotRunningException extends SingBoxException {
  /// Creates a "service not running" error.
  const SingBoxServiceNotRunningException(String message, {super.details})
    : super(SingBoxErrorCode.serviceNotRunning, message);

  @override
  String toString() => 'SingBoxServiceNotRunningException: $message';
}

/// The feature is not available on the current platform or OS version.
class SingBoxUnsupportedException extends SingBoxException {
  /// Creates an "unsupported" error.
  const SingBoxUnsupportedException(String message, {super.details})
    : super(SingBoxErrorCode.unsupported, message);

  @override
  String toString() => 'SingBoxUnsupportedException: $message';
}

/// A subscription could not be downloaded or contained no usable servers.
///
/// Thrown by `SingBox.addSubscription` and `SingBox.updateSubscription`;
/// the failed update is also recorded in `SingBoxSubscription.lastError`.
class SingBoxSubscriptionException extends SingBoxException {
  /// Creates a subscription error.
  const SingBoxSubscriptionException(
    String message, {
    this.url,
    this.statusCode,
    super.details,
  }) : super(SingBoxErrorCode.subscriptionFailed, message);

  /// The subscription URL.
  final String? url;

  /// The HTTP status code when the server answered with an error.
  final int? statusCode;

  @override
  String toString() => 'SingBoxSubscriptionException: $message';
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

  /// Dart only: the tunnel did not reach the expected state in time.
  static const timeout = 'TIMEOUT';

  /// Dart only: the operation was superseded by another one.
  static const cancelled = 'CANCELLED';

  /// Not supported on this platform.
  static const unsupported = 'UNSUPPORTED';

  /// Android only: an `Activity` is required but none is attached.
  static const noActivity = 'NO_ACTIVITY';

  /// Any other failure.
  static const internal = 'INTERNAL';

  /// Dart only: a subscription could not be downloaded or parsed.
  static const subscriptionFailed = 'SUBSCRIPTION_FAILED';
}
