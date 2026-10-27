import 'dart:io';

import 'package:flutter/material.dart';
import 'package:sing_box/sing_box.dart';

import 'format.dart';
import 'ui.dart';

/// Settings, permissions, clash mode, connections, NAT test and config viewer.
class ToolsPage extends StatefulWidget {
  const ToolsPage({super.key});

  @override
  State<ToolsPage> createState() => _ToolsPageState();
}

class _ToolsPageState extends State<ToolsPage> {
  final _singBox = SingBox.instance;
  SingBoxSettings _settings = const SingBoxSettings();
  bool? _vpnPermission;
  bool? _notificationPermission;
  SingBoxStunResult? _stun;
  bool _stunRunning = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final settings = await _singBox.getSettings();
    final vpn = await _singBox.hasVpnPermission();
    final notifications = await _singBox.hasNotificationPermission();
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _vpnPermission = vpn;
      _notificationPermission = notifications;
    });
  }

  Future<void> _set(String key, bool value) async {
    await _singBox.updateSetting(key, value);
    await _reload();
  }

  Future<void> _runStun() async {
    setState(() {
      _stun = null;
      _stunRunning = true;
    });
    try {
      await for (final result in _singBox.runStunTest()) {
        if (mounted) setState(() => _stun = result);
      }
    } on SingBoxException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _stunRunning = false);
    }
  }

  Future<void> _showConfig() async {
    final config = await _singBox.getLastConfig();
    if (!mounted) return;
    var text = config ?? 'No configuration yet';
    if (config != null) {
      try {
        text = await _singBox.formatConfig(config);
      } on SingBoxException {
        // Show the raw config.
      }
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Generated config'),
        content: SingleChildScrollView(
          child: SelectableText(
            text,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final connected = _singBox.isConnected;
    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          const SectionHeader('Settings'),
          SwitchListTile(
            title: const Text('Connect on app start'),
            value: _settings.autoConnectOnStart,
            onChanged: (v) => _set(SingBoxSettings.keyAutoConnectOnStart, v),
          ),
          SwitchListTile(
            title: const Text('Auto reconnect'),
            subtitle: Text(
              Platform.isIOS ? 'VPN On Demand' : 'Restart by the system',
            ),
            value: _settings.autoReconnectOnDisconnect,
            onChanged: (v) =>
                _set(SingBoxSettings.keyAutoReconnectOnDisconnect, v),
          ),
          if (Platform.isAndroid)
            SwitchListTile(
              title: const Text('Start on boot'),
              value: _settings.startOnBoot,
              onChanged: (v) => _set(SingBoxSettings.keyStartOnBoot, v),
            ),
          SwitchListTile(
            title: const Text('Kill switch'),
            subtitle: Text(
              Platform.isIOS
                  ? 'Include all networks'
                  : 'Enable "Block connections without VPN" in system settings',
            ),
            value: _settings.killSwitch,
            onChanged: (v) async {
              await _set(SingBoxSettings.keyKillSwitch, v);
              if (v && Platform.isAndroid) await _singBox.openVpnSettings();
            },
          ),
          const SectionHeader('Permissions'),
          ListTile(
            leading: const Icon(Icons.vpn_key_outlined),
            title: const Text('VPN permission'),
            subtitle: Text('${_vpnPermission ?? '…'}'),
            trailing: TextButton(
              onPressed: () async {
                await _singBox.requestVpnPermission();
                await _reload();
              },
              child: const Text('Request'),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.notifications_outlined),
            title: const Text('Notifications'),
            subtitle: Text('${_notificationPermission ?? '…'}'),
            trailing: TextButton(
              onPressed: () async {
                await _singBox.requestNotificationPermission();
                await _reload();
              },
              child: const Text('Request'),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.settings_outlined),
            title: const Text('System VPN settings'),
            onTap: _singBox.openVpnSettings,
          ),
          if (connected) ...[
            const SectionHeader('Routing mode'),
            StreamBuilder<SingBoxClashMode>(
              stream: _singBox.watchClashMode(),
              builder: (context, snapshot) {
                final mode = snapshot.data ?? SingBoxClashMode.none;
                if (!mode.isAvailable) {
                  return const ListTile(title: Text('Not available'));
                }
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: SegmentedButton<String>(
                    segments: [
                      for (final m in mode.modes)
                        ButtonSegment(value: m, label: Text(m)),
                    ],
                    selected: {mode.current},
                    onSelectionChanged: (s) => _singBox.setClashMode(s.first),
                  ),
                );
              },
            ),
            SectionHeader(
              'NAT / UDP test (STUN)',
              trailing: IconButton(
                icon: const Icon(Icons.play_arrow),
                onPressed: _stunRunning ? null : _runStun,
              ),
            ),
            ListTile(
              title: Text(_stun?.externalAddress ?? 'Not tested'),
              subtitle: Text(
                _stun == null
                    ? ''
                    : 'Mapping: ${_stun!.natMapping.name}, '
                          'filtering: ${_stun!.natFiltering.name}, '
                          'latency: ${_stun!.latency?.inMilliseconds ?? '-'} ms',
              ),
            ),
            const _ConnectionsSection(),
          ],
          const SectionHeader('Debug'),
          ListTile(
            leading: const Icon(Icons.data_object),
            title: const Text('Show generated config'),
            onTap: _showConfig,
          ),
          FutureBuilder<String>(
            future: _singBox.getSingBoxVersion(),
            builder: (context, snapshot) => ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('sing-box core'),
              subtitle: Text(snapshot.data ?? '…'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConnectionsSection extends StatelessWidget {
  const _ConnectionsSection();

  @override
  Widget build(BuildContext context) {
    final singBox = SingBox.instance;
    return StreamBuilder<List<SingBoxConnection>>(
      stream: singBox.watchConnections(),
      builder: (context, snapshot) {
        final active = (snapshot.data ?? const [])
            .where((c) => c.isActive)
            .take(50)
            .toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionHeader(
              'Active connections (${active.length})',
              trailing: IconButton(
                tooltip: 'Close all',
                icon: const Icon(Icons.clear_all),
                onPressed: singBox.closeAllConnections,
              ),
            ),
            for (final c in active)
              ListTile(
                dense: true,
                title: Text('${c.network.toUpperCase()} ${c.displayDestination}'),
                subtitle: Text(
                  '${c.outbound} · ${c.rule}'
                  '${c.processName == null ? '' : ' · ${c.processName}'}\n'
                  '↓ ${formatBytes(c.downloadTotal)}  ↑ ${formatBytes(c.uploadTotal)}',
                ),
                isThreeLine: true,
                trailing: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => singBox.closeConnection(c.id),
                ),
              ),
          ],
        );
      },
    );
  }
}
