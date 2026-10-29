import '../options.dart';

/// User facing behaviour settings persisted by the plugin.
///
/// Read with `SingBox.getSettings()` and store with `SingBox.saveSettings()`
/// or `SingBox.updateSetting()`. Native-relevant flags are applied to the VPN
/// service immediately (see [toServiceOptions]).
///
/// Routing preferences (bypass and block lists, DNS servers) are kept
/// separately in `SingBoxRoutingRules`.
class SingBoxSettings {
  /// Creates settings.
  const SingBoxSettings({
    this.autoConnectOnStart = false,
    this.autoReconnectOnDisconnect = false,
    this.killSwitch = false,
    this.startOnBoot = false,
    this.excludeLocalNetworks = true,
    this.excludeApns = true,
    this.disableMemoryLimit = false,
    this.quickSettingsTile = false,
    this.enforceRoutes = false,
    this.excludeCellularServices = false,
    this.excludeDeviceCommunication = false,
    this.excludeDefaultRoute = false,
    this.noDefaultRoute = false,
    this.excludeApnsRoute = false,
  });

  /// Setting key for [autoConnectOnStart], used by `SingBox.updateSetting()`.
  static const keyAutoConnectOnStart = 'autoConnectOnStart';

  /// Setting key for [autoReconnectOnDisconnect].
  static const keyAutoReconnectOnDisconnect = 'autoReconnectOnDisconnect';

  /// Setting key for [killSwitch].
  static const keyKillSwitch = 'killSwitch';

  /// Setting key for [startOnBoot].
  static const keyStartOnBoot = 'startOnBoot';

  /// Setting key for [excludeLocalNetworks].
  static const keyExcludeLocalNetworks = 'excludeLocalNetworks';

  /// Setting key for [excludeApns].
  static const keyExcludeApns = 'excludeApns';

  /// Setting key for [disableMemoryLimit].
  static const keyDisableMemoryLimit = 'disableMemoryLimit';

  /// Setting key for [quickSettingsTile].
  static const keyQuickSettingsTile = 'quickSettingsTile';

  /// Setting key for [enforceRoutes].
  static const keyEnforceRoutes = 'enforceRoutes';

  /// Setting key for [excludeCellularServices].
  static const keyExcludeCellularServices = 'excludeCellularServices';

  /// Setting key for [excludeDeviceCommunication].
  static const keyExcludeDeviceCommunication = 'excludeDeviceCommunication';

  /// Setting key for [excludeDefaultRoute].
  static const keyExcludeDefaultRoute = 'excludeDefaultRoute';

  /// Setting key for [noDefaultRoute].
  static const keyNoDefaultRoute = 'noDefaultRoute';

  /// Setting key for [excludeApnsRoute].
  static const keyExcludeApnsRoute = 'excludeApnsRoute';

  /// All valid setting keys.
  static const keys = [
    keyQuickSettingsTile,
    keyAutoConnectOnStart,
    keyAutoReconnectOnDisconnect,
    keyKillSwitch,
    keyStartOnBoot,
    keyExcludeLocalNetworks,
    keyExcludeApns,
    keyDisableMemoryLimit,
    keyEnforceRoutes,
    keyExcludeCellularServices,
    keyExcludeDeviceCommunication,
    keyExcludeDefaultRoute,
    keyNoDefaultRoute,
    keyExcludeApnsRoute,
  ];

  /// Connect to the active server automatically when
  /// `SingBox.initialize()` is called (i.e. when the app starts).
  final bool autoConnectOnStart;

  /// Keep the tunnel up and reconnect automatically after network changes or
  /// failures. iOS: VPN On Demand. Android: the service is restarted by the
  /// system (`START_STICKY`) and you can additionally ask the user to enable
  /// *Always-on VPN* via `SingBox.openVpnSettings()`.
  final bool autoReconnectOnDisconnect;

  /// Block traffic outside of the tunnel. iOS: `includeAllNetworks`.
  /// Android cannot enable this programmatically: the user has to turn on
  /// *Block connections without VPN* in system settings
  /// (`SingBox.openVpnSettings()`); while the tunnel is running,
  /// `strict_route` already prevents leaks.
  final bool killSwitch;

  /// Android: start the VPN with the last configuration after reboot.
  final bool startOnBoot;

  /// iOS: keep LAN traffic outside the tunnel when [killSwitch] is on.
  final bool excludeLocalNetworks;

  /// iOS 16.4+: let push notification traffic bypass the tunnel when
  /// [killSwitch] is on.
  final bool excludeApns;

  /// Disable the sing-box memory limit (not recommended on iOS, where the
  /// extension is killed above ~50 MB).
  final bool disableMemoryLimit;

  /// Android: show the plugin's Quick Settings tile (VPN toggle).
  final bool quickSettingsTile;

  /// iOS 14+: `protocolConfiguration.enforceRoutes` - without [killSwitch] the
  /// system scopes the tunnel's routes to the VPN and the excluded routes to
  /// the primary interface, overriding the routing of apps that bind to an
  /// interface. With [excludeLocalNetworks] LAN traffic stays outside.
  final bool enforceRoutes;

  /// iOS 16.4+: Wi-Fi Calling, MMS, SMS and Visual Voicemail bypass the
  /// tunnel when [killSwitch] is on.
  final bool excludeCellularServices;

  /// iOS 17.4+: `protocolConfiguration.excludeDeviceCommunication` -
  /// communication with paired devices bypasses the tunnel when [killSwitch]
  /// is on.
  final bool excludeDeviceCommunication;

  /// iOS: adds `0.0.0.0/31` and `::/127` to the excluded routes, which hides
  /// the VPN icon in the status bar (sing-box-for-apple's "Hide VPN Icon").
  final bool excludeDefaultRoute;

  /// iOS: route the address space in ranges (`1.0.0.0/8` … `128.0.0.0/1`)
  /// instead of a default route unless the configuration sets
  /// `route_address` (sing-box-for-apple's "No Default Route"; fixes HomeKit
  /// and some other system features).
  final bool noDefaultRoute;

  /// iOS: keep Apple push notifications outside the tunnel on every iOS
  /// version by excluding `17.0.0.0/8` and bypassing `push.apple.com` in the
  /// system HTTP proxy (unlike [excludeApns] it works without [killSwitch]).
  final bool excludeApnsRoute;

  /// Creates settings from a map (for deserialization). Unknown keys are
  /// ignored.
  factory SingBoxSettings.fromMap(Map<dynamic, dynamic> map) {
    bool read(String key, bool fallback) {
      final value = map[key];
      return value is bool ? value : fallback;
    }

    return SingBoxSettings(
      autoConnectOnStart: read(keyAutoConnectOnStart, false),
      autoReconnectOnDisconnect: read(keyAutoReconnectOnDisconnect, false),
      killSwitch: read(keyKillSwitch, false),
      startOnBoot: read(keyStartOnBoot, false),
      excludeLocalNetworks: read(keyExcludeLocalNetworks, true),
      excludeApns: read(keyExcludeApns, true),
      disableMemoryLimit: read(keyDisableMemoryLimit, false),
      quickSettingsTile: read(keyQuickSettingsTile, false),
      enforceRoutes: read(keyEnforceRoutes, false),
      excludeCellularServices: read(keyExcludeCellularServices, false),
      excludeDeviceCommunication: read(keyExcludeDeviceCommunication, false),
      excludeDefaultRoute: read(keyExcludeDefaultRoute, false),
      noDefaultRoute: read(keyNoDefaultRoute, false),
      excludeApnsRoute: read(keyExcludeApnsRoute, false),
    );
  }

  /// Converts the settings to a map (for serialization).
  Map<String, dynamic> toMap() => {
    keyAutoConnectOnStart: autoConnectOnStart,
    keyAutoReconnectOnDisconnect: autoReconnectOnDisconnect,
    keyKillSwitch: killSwitch,
    keyStartOnBoot: startOnBoot,
    keyExcludeLocalNetworks: excludeLocalNetworks,
    keyExcludeApns: excludeApns,
    keyDisableMemoryLimit: disableMemoryLimit,
    keyQuickSettingsTile: quickSettingsTile,
    keyEnforceRoutes: enforceRoutes,
    keyExcludeCellularServices: excludeCellularServices,
    keyExcludeDeviceCommunication: excludeDeviceCommunication,
    keyExcludeDefaultRoute: excludeDefaultRoute,
    keyNoDefaultRoute: noDefaultRoute,
    keyExcludeApnsRoute: excludeApnsRoute,
  };

  /// Returns a copy with [key] set to [value].
  ///
  /// Throws [ArgumentError] for an unknown key or a non-boolean value.
  SingBoxSettings withValue(String key, Object? value) {
    if (!keys.contains(key)) {
      throw ArgumentError.value(key, 'key', 'Unknown setting');
    }
    if (value is! bool) {
      throw ArgumentError.value(value, 'value', 'Setting $key expects a bool');
    }
    return SingBoxSettings.fromMap({...toMap(), key: value});
  }

  /// The native service options derived from these settings.
  SingBoxServiceOptions toServiceOptions() => SingBoxServiceOptions(
    startOnBoot: startOnBoot,
    onDemand: autoReconnectOnDisconnect,
    includeAllNetworks: killSwitch,
    excludeLocalNetworks: excludeLocalNetworks,
    excludeApns: excludeApns,
    quickSettingsTile: quickSettingsTile,
    enforceRoutes: enforceRoutes,
    excludeCellularServices: excludeCellularServices,
    excludeDeviceCommunication: excludeDeviceCommunication,
    excludeDefaultRoute: excludeDefaultRoute,
    noDefaultRoute: noDefaultRoute,
    excludeApnsRoute: excludeApnsRoute,
  );

  /// Creates a copy with modified fields.
  SingBoxSettings copyWith({
    bool? autoConnectOnStart,
    bool? autoReconnectOnDisconnect,
    bool? killSwitch,
    bool? startOnBoot,
    bool? excludeLocalNetworks,
    bool? excludeApns,
    bool? disableMemoryLimit,
    bool? quickSettingsTile,
    bool? enforceRoutes,
    bool? excludeCellularServices,
    bool? excludeDeviceCommunication,
    bool? excludeDefaultRoute,
    bool? noDefaultRoute,
    bool? excludeApnsRoute,
  }) {
    return SingBoxSettings(
      autoConnectOnStart: autoConnectOnStart ?? this.autoConnectOnStart,
      autoReconnectOnDisconnect:
          autoReconnectOnDisconnect ?? this.autoReconnectOnDisconnect,
      killSwitch: killSwitch ?? this.killSwitch,
      startOnBoot: startOnBoot ?? this.startOnBoot,
      excludeLocalNetworks: excludeLocalNetworks ?? this.excludeLocalNetworks,
      excludeApns: excludeApns ?? this.excludeApns,
      disableMemoryLimit: disableMemoryLimit ?? this.disableMemoryLimit,
      quickSettingsTile: quickSettingsTile ?? this.quickSettingsTile,
      enforceRoutes: enforceRoutes ?? this.enforceRoutes,
      excludeCellularServices:
          excludeCellularServices ?? this.excludeCellularServices,
      excludeDeviceCommunication:
          excludeDeviceCommunication ?? this.excludeDeviceCommunication,
      excludeDefaultRoute: excludeDefaultRoute ?? this.excludeDefaultRoute,
      noDefaultRoute: noDefaultRoute ?? this.noDefaultRoute,
      excludeApnsRoute: excludeApnsRoute ?? this.excludeApnsRoute,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SingBoxSettings &&
      other.autoConnectOnStart == autoConnectOnStart &&
      other.autoReconnectOnDisconnect == autoReconnectOnDisconnect &&
      other.killSwitch == killSwitch &&
      other.startOnBoot == startOnBoot &&
      other.excludeLocalNetworks == excludeLocalNetworks &&
      other.excludeApns == excludeApns &&
      other.disableMemoryLimit == disableMemoryLimit &&
      other.quickSettingsTile == quickSettingsTile &&
      other.enforceRoutes == enforceRoutes &&
      other.excludeCellularServices == excludeCellularServices &&
      other.excludeDeviceCommunication == excludeDeviceCommunication &&
      other.excludeDefaultRoute == excludeDefaultRoute &&
      other.noDefaultRoute == noDefaultRoute &&
      other.excludeApnsRoute == excludeApnsRoute;

  @override
  int get hashCode => Object.hash(
    autoConnectOnStart,
    autoReconnectOnDisconnect,
    killSwitch,
    startOnBoot,
    excludeLocalNetworks,
    excludeApns,
    disableMemoryLimit,
    quickSettingsTile,
    enforceRoutes,
    excludeCellularServices,
    excludeDeviceCommunication,
    excludeDefaultRoute,
    noDefaultRoute,
    excludeApnsRoute,
  );

  @override
  String toString() => 'SingBoxSettings(${toMap()})';
}
