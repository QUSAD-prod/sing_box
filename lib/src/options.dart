/// Options passed to `SingBox.initialize()`.
class SingBoxOptions {
  /// Creates initialization options.
  const SingBoxOptions({
    this.android = const SingBoxAndroidOptions(),
    this.ios = const SingBoxIosOptions(),
    this.logMaxLines = 3000,
    this.debug = false,
  });

  /// Android specific options (foreground service notification).
  final SingBoxAndroidOptions android;

  /// iOS specific options (app group, Network Extension identifiers).
  final SingBoxIosOptions ios;

  /// How many log lines the core keeps in memory for `watchLogs()`.
  final int logMaxLines;

  /// Enables sing-box debug mode (verbose internal logging, pprof hooks).
  final bool debug;

  /// Serializes the options for the platform channel.
  Map<String, dynamic> toMap() => {
    'logMaxLines': logMaxLines,
    'debug': debug,
    'android': android.toMap(),
    'ios': ios.toMap(),
  };
}

/// Android options: the foreground service notification shown while the VPN
/// is running.
///
/// Android requires every VPN service to run as a foreground service with a
/// visible notification.
class SingBoxAndroidOptions {
  /// Creates Android options.
  const SingBoxAndroidOptions({
    this.notificationChannelId = 'sing_box_vpn',
    this.notificationChannelName = 'VPN',
    this.notificationTitle,
    this.notificationContent,
    this.notificationIcon,
    this.showTrafficInNotification = true,
    this.showStopAction = true,
    this.stopActionTitle = 'Stop',
    this.sessionName,
  });

  /// Id of the notification channel created for the service.
  final String notificationChannelId;

  /// User visible name of the notification channel.
  final String notificationChannelName;

  /// Notification title. Defaults to the application label.
  final String? notificationTitle;

  /// Notification text. Defaults to `Connected`.
  final String? notificationContent;

  /// Name of a drawable resource of the host app used as the small icon,
  /// e.g. `ic_vpn_key` for `android/app/src/main/res/drawable/ic_vpn_key.xml`.
  /// Defaults to the app icon. Use a monochrome vector drawable for best
  /// results on modern Android versions.
  final String? notificationIcon;

  /// Whether the notification shows the current upload/download speed.
  final bool showTrafficInNotification;

  /// Whether the notification has a "Stop" action button.
  final bool showStopAction;

  /// Label of the stop action button.
  final String stopActionTitle;

  /// VPN session name shown in Android system settings. Defaults to the
  /// application label.
  final String? sessionName;

  /// Serializes the options for the platform channel.
  Map<String, dynamic> toMap() => {
    'notificationChannelId': notificationChannelId,
    'notificationChannelName': notificationChannelName,
    'notificationTitle': notificationTitle,
    'notificationContent': notificationContent,
    'notificationIcon': notificationIcon,
    'showTrafficInNotification': showTrafficInNotification,
    'showStopAction': showStopAction,
    'stopActionTitle': stopActionTitle,
    'sessionName': sessionName,
  };
}

/// iOS options: identifiers of the app group and the Packet Tunnel Network
/// Extension.
///
/// The defaults follow the conventions used in the setup guide, so most apps
/// do not need to set anything.
class SingBoxIosOptions {
  /// Creates iOS options.
  const SingBoxIosOptions({
    this.appGroup,
    this.tunnelBundleIdentifier,
    this.profileName,
    this.serverAddress,
  });

  /// App group shared by the app and the extension. Defaults to
  /// `group.<main bundle identifier>`.
  final String? appGroup;

  /// Bundle identifier of the Packet Tunnel extension. Defaults to
  /// `<main bundle identifier>.PacketTunnel`.
  final String? tunnelBundleIdentifier;

  /// Name of the VPN profile shown in iOS Settings → VPN. Defaults to the
  /// app display name.
  final String? profileName;

  /// "Server" text shown in iOS Settings → VPN. Defaults to `sing-box`.
  final String? serverAddress;

  /// Serializes the options for the platform channel.
  Map<String, dynamic> toMap() => {
    'appGroup': appGroup,
    'tunnelBundleIdentifier': tunnelBundleIdentifier,
    'profileName': profileName,
    'serverAddress': serverAddress,
  };
}

/// Persistent behaviour of the VPN service that is applied natively.
///
/// Usually managed through `SingBoxSettings`; see
/// `SingBox.setServiceOptions()`.
class SingBoxServiceOptions {
  /// Creates service options.
  const SingBoxServiceOptions({
    this.startOnBoot = false,
    this.onDemand = false,
    this.includeAllNetworks = false,
    this.excludeLocalNetworks = true,
    this.excludeApns = true,
    this.quickSettingsTile = false,
    this.enforceRoutes = false,
    this.excludeCellularServices = false,
    this.excludeDeviceCommunication = false,
    this.excludeDefaultRoute = false,
    this.noDefaultRoute = false,
    this.excludeApnsRoute = false,
    this.allowBypass = false,
  });

  /// Android: start the VPN with the last configuration after the device
  /// boots or the app is updated (requires a granted VPN permission).
  final bool startOnBoot;

  /// iOS: keep the VPN connected and reconnect automatically (VPN On Demand
  /// with a "connect on any network" rule).
  final bool onDemand;

  /// iOS: route all traffic, including traffic of system services, through
  /// the tunnel and block traffic while it reconnects (kill switch).
  final bool includeAllNetworks;

  /// iOS: keep local network (LAN) traffic outside of the tunnel when
  /// [includeAllNetworks] is enabled.
  final bool excludeLocalNetworks;

  /// iOS 16.4+: let Apple Push Notification service traffic bypass the
  /// tunnel when [includeAllNetworks] is enabled.
  final bool excludeApns;

  /// Android: enables the plugin's Quick Settings tile, which toggles the VPN
  /// with the last configuration. Use `SingBox.requestAddQuickSettingsTile()`
  /// to prompt the user to add it (Android 13+).
  final bool quickSettingsTile;

  /// iOS 14+: `protocolConfiguration.enforceRoutes` - without [includeAllNetworks] the
  /// system scopes the tunnel's routes to the VPN and the excluded routes to
  /// the primary interface, overriding the routing of apps that bind to an
  /// interface. With [excludeLocalNetworks] LAN traffic stays outside.
  final bool enforceRoutes;

  /// iOS 16.4+: Wi-Fi Calling, MMS, SMS and Visual Voicemail bypass the
  /// tunnel when [includeAllNetworks] is on.
  final bool excludeCellularServices;

  /// iOS 17.4+: `protocolConfiguration.excludeDeviceCommunication` -
  /// communication with paired devices bypasses the tunnel when [includeAllNetworks]
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
  /// system HTTP proxy (unlike [excludeApns] it works without [includeAllNetworks]).
  final bool excludeApnsRoute;

  /// Android: `VpnService.Builder.allowBypass()` - apps may bind their
  /// sockets to another network and leave the VPN. Applied when the tunnel
  /// starts.
  final bool allowBypass;

  /// Serializes the options for the platform channel.
  Map<String, dynamic> toMap() => {
    'quickSettingsTile': quickSettingsTile,
    'startOnBoot': startOnBoot,
    'onDemand': onDemand,
    'includeAllNetworks': includeAllNetworks,
    'excludeLocalNetworks': excludeLocalNetworks,
    'excludeAPNs': excludeApns,
    'enforceRoutes': enforceRoutes,
    'excludeCellularServices': excludeCellularServices,
    'excludeDeviceCommunication': excludeDeviceCommunication,
    'excludeDefaultRoute': excludeDefaultRoute,
    'noDefaultRoute': noDefaultRoute,
    'excludeAPNsRoute': excludeApnsRoute,
    'allowBypass': allowBypass,
  };
}

/// Result of `SingBox.requestAddQuickSettingsTile()`.
enum SingBoxQuickTileResult {
  /// The user added the tile.
  added,

  /// The tile was already added.
  alreadyAdded,

  /// The user declined.
  declined,

  /// Not supported (Android below 13, iOS, or no foreground Activity).
  unsupported;

  /// Parses the wire value.
  static SingBoxQuickTileResult fromString(String? value) {
    for (final v in values) {
      if (v.name == value) return v;
    }
    return unsupported;
  }
}
