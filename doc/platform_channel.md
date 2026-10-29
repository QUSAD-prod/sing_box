# Platform channel contract

This document is the single source of truth for the messages exchanged between
the Dart side of `sing_box` (`MethodChannelSingBox`) and the native Android
(Kotlin) and iOS (Swift) implementations. Every native implementation must
follow it exactly; the Dart side relies on the names, argument keys and payload
shapes described here.

All values use the Flutter standard message codec. "int" means a 64-bit integer
on the wire (Kotlin `Long`/`Int`, Swift `Int`/`Int64`). Optional values may be
omitted or sent as `null`. Unknown keys must be ignored on both sides.

## Errors

Failures are reported as `PlatformException`s (`result.error(code, message,
details)` / `FlutterError`). The Dart side maps these codes to typed exceptions:

| Code | Meaning |
| --- | --- |
| `NOT_INITIALIZED` | `initialize` has not been called |
| `INVALID_ARGUMENT` | A required argument is missing or malformed |
| `INVALID_CONFIG` | sing-box rejected the configuration (message = sing-box error) |
| `PERMISSION_DENIED` | VPN permission not granted / profile not installed |
| `SERVICE_NOT_RUNNING` | The operation requires a running service |
| `START_FAILED` | The tunnel could not be started |
| `COMMAND_FAILED` | A libbox command-client call failed (message = libbox error) |
| `UNSUPPORTED` | Not supported on this platform/OS version |
| `NO_ACTIVITY` | Android only: an Activity is required but not attached |
| `INTERNAL` | Anything else |

## Method channel `sing_box`

### `initialize`

Must be called once per engine before any other method (except
`getPlatformVersion`). Idempotent. Performs `Libbox.setup` (once per process),
creates the notification channel (Android), loads the VPN profile (iOS) and
starts status tracking.

Arguments (map):

| Key | Type | Description |
| --- | --- | --- |
| `logMaxLines` | int | Log buffer size kept by libbox (default 3000) |
| `debug` | bool | Enables libbox debug mode (default false) |
| `android` | map? | Android options, see below |
| `ios` | map? | iOS options, see below |

`android` map:

| Key | Type | Default |
| --- | --- | --- |
| `notificationChannelId` | String | `"sing_box_vpn"` |
| `notificationChannelName` | String | `"VPN"` |
| `notificationTitle` | String? | application label |
| `notificationContent` | String? | `"Connected"`; the service may append traffic speed |
| `notificationIcon` | String? | drawable resource name in the host app, e.g. `"ic_vpn"`; falls back to the app icon |
| `showTrafficInNotification` | bool | `true` - updates the notification with ↑/↓ speed every second |
| `showStopAction` | bool | `true` - adds a "Stop" action button (never shown under Always-on lockdown) |
| `stopActionTitle` | String | `"Stop"` |
| `sessionName` | String? | `VpnService.Builder.setSession`, defaults to the app label |

`ios` map:

| Key | Type | Default |
| --- | --- | --- |
| `appGroup` | String? | `"group.<main bundle id>"` |
| `tunnelBundleIdentifier` | String? | `"<main bundle id>.PacketTunnel"` |
| `profileName` | String? | `CFBundleDisplayName` / `CFBundleName` |
| `serverAddress` | String? | `"sing-box"` - shown in iOS Settings → VPN |

Returns a map:

| Key | Type | Description |
| --- | --- | --- |
| `singBoxVersion` | String | `Libbox.version()` |
| `status` | String | Current status (see *Status values*) |
| `workingDirectory` | String | Absolute libbox working path |

### Information

| Method | Arguments | Returns |
| --- | --- | --- |
| `getPlatformVersion` | – | String, e.g. `"Android 15"`, `"iOS 18.2"` |
| `getSingBoxVersion` | – | String, `Libbox.version()` |
| `checkConfig` | `{config: String}` | `null`; throws `INVALID_CONFIG` with the sing-box error message |
| `formatConfig` | `{config: String}` | String (pretty-printed config); throws `INVALID_CONFIG` |

### Permissions

| Method | Arguments | Returns |
| --- | --- | --- |
| `hasVpnPermission` | – | bool. Android: `VpnService.prepare(context) == null`. iOS: a `NETunnelProviderManager` for `tunnelBundleIdentifier` exists in preferences |
| `requestVpnPermission` | – | bool. Android: launches the system consent dialog through the attached Activity and resolves with the result. iOS: creates/saves the `NETunnelProviderManager` (the system shows the "Add VPN Configurations" alert) and resolves `true` on success, `false` if the user declined |
| `hasNotificationPermission` | – | bool. Android 13+: `POST_NOTIFICATIONS` granted; below 13: `true`. iOS: `UNUserNotificationCenter` authorization status is authorized/provisional |
| `requestNotificationPermission` | – | bool. Android 13+: runtime permission request through the Activity. iOS: `requestAuthorization([.alert, .sound, .badge])` |
| `openVpnSettings` | – | `null`. Android: opens `Settings.ACTION_VPN_SETTINGS` (where the user enables *Always-on VPN* and *Block connections without VPN*). iOS: opens the app's settings page |

### Service control

#### `start`

Arguments:

| Key | Type | Description |
| --- | --- | --- |
| `config` | String | Complete sing-box JSON configuration (required) |
| `oomKiller` | String | Memory monitor (libbox OOM killer): `platformDefault` (iOS: `enabled`, Android: `off`), `off` (`SetupOptions.oomKillerEnabled = false`), `reportOnly` (`oomKillerEnabled = true`, `oomKillerDisabled = true`: reports only) or `enabled` (`oomKillerEnabled = true`, `oomKillerDisabled = false`). Persisted for starts without the app (Android boot/tile/always-on: `ServiceSettings`; iOS on-demand: app group defaults `sing_box.oom_killer`). Android applies it with `Libbox.reloadSetupOptions` before creating the command server; iOS passes it to the extension as start option `oomKiller`. Default `platformDefault` |
| `memoryLimit` | int | `SetupOptions.oomMemoryLimit` in bytes, 0 = default (Android: available system memory; iOS: the 50 MB Network Extension limit). Persisted like `oomKiller` (iOS: `sing_box.memory_limit`, start option `memoryLimit`). Default 0 |
| `disableMemoryLimit` | bool | Pre-1.1.0 form of `oomKiller: off`, still sent (`true` when `oomKiller` is `off`); used only when `oomKiller` is missing. Default false |

Behaviour:

* Validates the config with `Libbox.checkConfig` first and throws
  `INVALID_CONFIG` on failure.
* Persists the config as the *last config* (used by Android always-on/boot
  start and by the iOS extension on on-demand reconnects). Android: file
  `<filesDir>/sing-box/last_config.json`. iOS: file
  `<app group container>/sing-box/config.json`, written before the tunnel is
  started.
* Android: throws `PERMISSION_DENIED` if `VpnService.prepare` returns an
  intent; otherwise starts the foreground VPN service and resolves as soon as
  the service was asked to start (the status stream reports progress).
* Both platforms: when the tunnel was not running, the `connecting` status
  event must be emitted **before** the method result is delivered, and the
  outcome follows on the status stream: `connected`, or `disconnected` with
  `error` set to the exact core/OS error. The Dart `connect()` waits for this
  outcome; a `disconnected` event without a preceding `connecting` and before
  the result is treated as the end of the previous session unless it carries
  a new `error`.
* iOS: throws `PERMISSION_DENIED` if the profile is missing; enables the
  manager, applies `serviceOptions` (on-demand, includeAllNetworks, …), saves
  it and calls `startVPNTunnel`.
* If the service is already running it is reloaded with the new config
  (equivalent to `reload`).

#### Other control methods

| Method | Arguments | Behaviour |
| --- | --- | --- |
| `stop` | – | Stops the tunnel. Resolves once the stop was requested. iOS also disables on-demand so the system does not reconnect |
| `reload` | `{config: String?}` | If `config` is given it replaces the last config (validated first). Reloads the running service with `CommandServer.startOrReloadService`. Throws `SERVICE_NOT_RUNNING` if stopped; a failed reload stops the tunnel (status `disconnected` with `error`) and throws `START_FAILED` |
| `getStatus` | – | String status |
| `getStartedAt` | – | int? - epoch milliseconds when the current session started, `null` when not running |
| `getLastConfig` | – | String? - last persisted config |
| `setServiceOptions` | map (below) | Persists and applies service options. Returns `null` |

`setServiceOptions` map:

| Key | Type | Platform | Description |
| --- | --- | --- | --- |
| `startOnBoot` | bool | Android | Start the service with the last config after `BOOT_COMPLETED` / package update (requires granted VPN permission) |
| `onDemand` | bool | iOS | `isOnDemandEnabled` with a connect rule for any interface (auto reconnect / always on) |
| `includeAllNetworks` | bool | iOS 14+ | `protocolConfiguration.includeAllNetworks` (kill switch) |
| `excludeLocalNetworks` | bool | iOS 14+ | `protocolConfiguration.excludeLocalNetworks` |
| `excludeAPNs` | bool | iOS 16.4+ | `excludeAPNs` (push notifications bypass the tunnel) |
| `enforceRoutes` | bool | iOS 14+ | `protocolConfiguration.enforceRoutes` |
| `excludeCellularServices` | bool | iOS 16.4+ | `excludeCellularServices` (Wi-Fi Calling, MMS, SMS, Visual Voicemail bypass the tunnel) |
| `excludeDeviceCommunication` | bool | iOS 17.4+ | `excludeDeviceCommunication` |
| `excludeDefaultRoute` | bool | iOS | The extension adds `0.0.0.0/31` and `::/127` to the excluded routes (hides the VPN icon). Read by the extension in `openTun`: applies on the next start or reload |
| `noDefaultRoute` | bool | iOS | Without `route_address`, the extension routes `1.0.0.0/8` … `128.0.0.0/1` and `100::/8` … `8000::/1` instead of default routes. Next start or reload |
| `excludeAPNsRoute` | bool | iOS | The extension excludes `17.0.0.0/8` and adds `push.apple.com` to the system proxy bypass list. Next start or reload |
| `quickSettingsTile` | bool | Android | Enables the plugin's Quick Settings `TileService` component (declared disabled in the manifest, toggled with `PackageManager.setComponentEnabledSetting`). The tile starts the VPN with the last config / stops it, reflects the live status, and opens the app (PendingIntent overload of `startActivityAndCollapse` on API 34+) when the VPN permission is missing |

#### `requestAddQuickSettingsTile`

Android 13+ only: enables the tile component if needed and calls
`StatusBarManager.requestAddTileService`. Returns a String:
`"added"`, `"alreadyAdded"`, `"declined"` or `"unsupported"` (below Android 13,
on iOS, or when no Activity is attached). Arguments: `{label: String?}`
(defaults to the app label). Tile icon: drawable `notificationIcon` from
`initialize`, else the app icon.

### libbox command client operations

These forward to a libbox standalone command client
(`Libbox.newStandaloneCommandClient()`) connected to the running service. They
throw `SERVICE_NOT_RUNNING` when the service is stopped and `COMMAND_FAILED`
when libbox returns an error.

| Method | Arguments | libbox call |
| --- | --- | --- |
| `selectOutbound` | `{groupTag: String, outboundTag: String}` | `selectOutbound(groupTag, outboundTag)` |
| `urlTest` | `{tag: String}` | `urlTest(tag)` - group or single outbound; results arrive via the `groups`/`outbounds` streams |
| `setClashMode` | `{mode: String}` | `setClashMode(mode)` |
| `closeConnection` | `{id: String}` | `closeConnection(id)` |
| `closeAllConnections` | – | `closeConnections()` |
| `getSystemProxyStatus` | – | `getSystemProxyStatus()`; returns `{available: bool, enabled: bool}` |
| `setSystemProxyEnabled` | `{enabled: bool}` | `setSystemProxyEnabled(enabled)`. The handler persists the choice for later sessions (Android: `ServiceSettings.systemProxyEnabled`; iOS: app group defaults `sing_box.system_proxy_enabled`; both default `true`) and applies it: Android reloads the service so `openTun` calls (or skips) `VpnService.Builder.setHttpProxy`; iOS updates `NEProxySettings.httpEnabled/httpsEnabled` with `setTunnelNetworkSettings`. `openTun` applies the TUN `platform.http_proxy` only when the stored value is `true`; the status reports `available` when the TUN options enable the HTTP proxy (Android: and Android 10+) and `enabled` when it was applied |
| `clearLogs` | – | `clearLogs()` |
| `setGroupExpand` | `{groupTag: String, expand: bool}` | `setGroupExpand(groupTag, expand)` |

### Latency measurements

The Dart side measures HTTP latency through a proxy itself: while the tunnel is
connected it connects to the probe address of the running config (route rules
with `override_address`, see `SingBoxConfigBuilder`), otherwise to a probe
core started with `startProbe`. TCP and ICMP measurements are native because
they must bypass the tunnel.

| Method | Arguments | Result |
| --- | --- | --- |
| `startProbe` | `{config: String}` | `null`. Starts (or replaces) the probe core: a second libbox service (`CommandServer` without `Start()`, so no command socket) in the app process, running a config without TUN (`direct` inbounds on `127.0.0.1`). Android: its sockets are protected with `VpnService.protect` while the VPN service runs. Throws `INVALID_CONFIG` / `START_FAILED` |
| `stopProbe` | – | `null`. Stops the probe core; no-op without one |
| `pingServer` | `{method: "tcp" \| "icmp", host: String, port: int?, timeoutMs: int}` | Map `{success: bool, ping: int (ms), address: String? (IP used), error: String?}`. Measured outside the tunnel: the host is resolved by the underlying network (not the tunnel or FakeIP). Android protects the sockets while the VPN service runs; iOS runs the measurement in the extension (`sendProviderMessage` with `{"command": "ping", "method", "host", "port", "timeoutMs"}`, the reply is the JSON result map; the extension binds the sockets and the DNS query to the physical interface) while the tunnel is connected, in the app otherwise. `tcp`: time of the TCP handshake with `host:port`. `icmp`: round trip of one echo request (unprivileged ICMP datagram socket; ICMPv6 for IPv6). A failed measurement is a result with `success: false`, not an error |

### Key/value storage

A tiny persistent string store used by the Dart side for settings, server
profiles and routing rules. Android: `SharedPreferences` named `sing_box`.
iOS: `UserDefaults(suiteName: appGroup)` (falls back to `.standard`), so values
are also visible to the extension.

| Method | Arguments | Returns |
| --- | --- | --- |
| `storageRead` | `{key: String}` | String? |
| `storageWrite` | `{key: String, value: String?}` | `null`; `value == null` removes the key |

## Status values

The status is always one of `"disconnected"`, `"connecting"`,
`"connected"`, `"disconnecting"`.

* Android: mapped from the service state machine (Stopped / Starting /
  Started / Stopping). The service reports `connected` only after
  `startOrReloadService` succeeded.
* iOS: mapped from `NEVPNStatus` (`invalid`/`disconnected` → disconnected,
  `connecting`/`reasserting` → connecting, `connected` → connected,
  `disconnecting` → disconnecting).

## Event channels

Every event channel follows the same rules:

* Native starts producing events in `onListen` and stops (disconnecting any
  libbox command client it created) in `onCancel`.
* Events are delivered on the platform main thread.
* Streams backed by a libbox command client (`stats`, `logs`, `groups`,
  `outbounds`, `clash_mode`, `connections`) keep trying to connect while the
  service is not running (retry every second) and reconnect automatically
  after the service restarts. They never emit errors for "service not
  running"; they just stay silent.

### `sing_box/status`

Emits on every change and once immediately on listen:

```
{
  "status": "connected",
  "startedAt": 1730000000000,     // int?, epoch ms, null when not connected
  "error": "start service: ..."   // String?, last start/stop error, otherwise null
}
```

`error` is set when the tunnel stops because of a failure (invalid config at
runtime, permission revoked, crash) and is cleared on the next successful
start.

### `sing_box/stats`

libbox `CommandStatus` with `statusInterval = 1s` (1_000_000_000 ns):

```
{
  "uplink": 1024,          // bytes/s
  "downlink": 4096,        // bytes/s
  "uplinkTotal": 100000,   // bytes since start
  "downlinkTotal": 500000, // bytes since start
  "connectionsIn": 3,
  "connectionsOut": 5,
  "memory": 31457280,      // bytes
  "goroutines": 52,
  "trafficAvailable": true
}
```

### `sing_box/logs`

libbox `CommandLog`. Events:

```
{ "type": "logs", "reset": false, "entries": [ { "level": 2, "message": "..." } ] }
{ "type": "defaultLevel", "level": 2 }
{ "type": "clear" }
```

`level` uses sing-box numbering: 0 panic, 1 fatal, 2 error, 3 warn, 4 info,
5 debug, 6 trace.

### `sing_box/groups`

libbox `CommandGroup`. Emits the full list on every update:

```
[
  {
    "tag": "proxy", "type": "selector", "selectable": true,
    "selected": "node-1", "isExpand": true,
    "items": [
      { "tag": "node-1", "type": "vless", "urlTestTime": 1730000000000, "urlTestDelay": 120 }
    ]
  }
]
```

`urlTestTime` is epoch ms (0 = never tested), `urlTestDelay` is ms (0 = failed
or never tested).

### `sing_box/outbounds`

libbox `CommandOutbounds`. Emits the full list of outbounds with their last
URL test result, same item shape as `groups[].items`.

### `sing_box/clash_mode`

libbox `CommandClashMode`:

```
{ "modes": ["Rule", "Global", "Direct"], "current": "Rule" }
```

Emitted once on initialization (`InitializeClashMode`) and on every change
(`UpdateClashMode`, with the last known `modes`). `modes` is empty when the
config has no clash API / mode rules.

### `sing_box/connections`

libbox `CommandConnections`. Native keeps a `libbox.Connections` instance,
applies every `ConnectionEvents` (`applyEvents`), and emits a snapshot of
**all** connections (active and recently closed, sorted by date, newest first)
at most once per second:

```
[
  {
    "id": "...", "inbound": "tun-in", "inboundType": "tun", "ipVersion": 4,
    "network": "tcp", "source": "172.19.0.1:51234",
    "destination": "1.1.1.1:443", "domain": "one.one.one.one",
    "protocol": "tls", "user": "", "fromOutbound": "",
    "createdAt": 1730000000000, "closedAt": 0,
    "uplink": 10, "downlink": 20, "uplinkTotal": 1000, "downlinkTotal": 2000,
    "rule": "final", "outbound": "proxy", "outboundType": "vless",
    "chain": ["proxy", "node-1"],
    "processName": "com.example.app"   // Android package name / process path if known
  }
]
```

### `sing_box/notifications`

Notifications sent by the core through `PlatformInterface.sendNotification`
(for example rule-set update failures):

```
{ "identifier": "...", "typeName": "...", "typeId": 1, "title": "...",
  "subtitle": "...", "body": "...", "openUrl": "https://..." }
```

Android delivers them while the plugin is attached (the service also shows
them as system notifications). iOS posts them as local notifications from the
extension and forwards them to the app through the shared
`UserDefaults`/Darwin notification (best effort).

### `sing_box/network_quality`

One-shot stream. `receiveBroadcastStream(arguments)` with:

```
{ "configUrl": String?, "outboundTag": String?, "serial": bool,
  "maxRuntimeSeconds": int, "http3": bool }
```

Starts `CommandClient.startNetworkQualityTest` (defaults: libbox
`NetworkQualityDefaultConfigURL`, outbound `""` = default route,
`serial=false`, `maxRuntimeSeconds = NetworkQualityDefaultMaxRuntimeSeconds`,
`http3=false`). Emits progress events, then one result event, then
end-of-stream (`EventSink.endOfStream()`):

```
{ "type": "progress", "phase": 1, "downloadCapacity": 12345678, "uploadCapacity": 0,
  "downloadRPM": 0, "uploadRPM": 0, "idleLatencyMs": 35, "elapsedMs": 2000,
  "downloadCapacityAccuracy": 0, "uploadCapacityAccuracy": 0,
  "downloadRPMAccuracy": 0, "uploadRPMAccuracy": 0 }
{ "type": "result", ...same fields without phase/elapsedMs }
```

Capacities are bits per second. Phases: 0 idle, 1 download, 2 upload, 3 done.
Accuracy: 0 low, 1 medium, 2 high. On failure the stream emits an error
(`FlutterError(code: "COMMAND_FAILED", message)`) and ends. Cancelling the
subscription closes the libbox session. While the service is stopped the test
runs directly in the app process (`Libbox.newNetworkQualityTest()`,
`outboundTag` ignored) and measures the connection without the tunnel.

### `sing_box/stun`

One-shot stream like `network_quality` (direct `Libbox.newSTUNTest()` while
the service is stopped). Arguments
`{ "server": String?, "outboundTag": String? }` (defaults:
`STUNDefaultServer`, `""`). Events:

```
{ "type": "progress", "phase": 0, "externalAddr": "1.2.3.4:5678", "latencyMs": 40,
  "natMapping": 1, "natFiltering": 1 }
{ "type": "result", "externalAddr": "1.2.3.4:5678", "latencyMs": 40,
  "natMapping": 1, "natFiltering": 1, "natTypeSupported": true }
```

## Crash and out-of-memory reports

libbox writes them below the working directory: `crash_reports/<time>/`
(`go.log` with the Go crash output, archived by `Libbox.setup` of the next
process of the same `crashReportSource`) and `oom_reports/<time>/`. Before
creating the tunnel's command server both platforms call
`Libbox.promoteOOMDraft()` (iOS: in the extension), which files the memory
pressure recorded by the previous session. `SetupOptions.platformMetadata`
carries the OS and device model (iOS extension: also the Network Extension
options). The Dart side reads the directories itself
(`SingBox.getCoreReports()`).

## Files and directories

| Purpose | Android | iOS |
| --- | --- | --- |
| libbox base path (`command.sock` lives here) | `context.filesDir` | app group container |
| libbox working path | `<filesDir>/sing-box` | `<container>/sing-box` |
| libbox temp path | `context.cacheDir` | `<container>/Library/Caches/sing-box` |
| last config | `<working>/last_config.json` | `<working>/config.json` |
| service options | `SharedPreferences("sing_box_service")` | `UserDefaults(suiteName: appGroup)` key `sing_box.service_options` |

The iOS extension resolves the app group from
`(protocolConfiguration as NETunnelProviderProtocol).providerConfiguration["appGroup"]`
(written by the plugin when it saves the profile), falling back to the
`SingBoxAppGroup` key in the extension's `Info.plist`.
