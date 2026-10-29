/// State of the system HTTP proxy announced by the VPN
/// (`SingBoxLocalProxy.systemProxy`), see `SingBox.getSystemProxyStatus()`.
class SingBoxSystemProxyStatus {
  /// Creates a status.
  const SingBoxSystemProxyStatus({
    this.available = false,
    this.enabled = false,
  });

  /// No system proxy (the tunnel is stopped or its configuration has no TUN
  /// `platform.http_proxy`).
  static const unavailable = SingBoxSystemProxyStatus();

  /// Parses the result of the `getSystemProxyStatus` platform call.
  factory SingBoxSystemProxyStatus.fromMap(Map<dynamic, dynamic> map) =>
      SingBoxSystemProxyStatus(
        available: map['available'] == true,
        enabled: map['enabled'] == true,
      );

  /// Whether the running configuration sets a system proxy (Android: also
  /// requires Android 10+).
  final bool available;

  /// Whether the system proxy is currently applied.
  final bool enabled;

  @override
  bool operator ==(Object other) =>
      other is SingBoxSystemProxyStatus &&
      other.available == available &&
      other.enabled == enabled;

  @override
  int get hashCode => Object.hash(available, enabled);

  @override
  String toString() =>
      'SingBoxSystemProxyStatus(available: $available, enabled: $enabled)';
}
