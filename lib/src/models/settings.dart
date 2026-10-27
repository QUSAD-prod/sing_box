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
      other.quickSettingsTile == quickSettingsTile;

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
  );

  @override
  String toString() => 'SingBoxSettings(${toMap()})';
}
