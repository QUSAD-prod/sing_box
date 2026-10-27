import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sing_box/sing_box.dart';

import 'format.dart';
import 'ui.dart';

/// Connection status, the connect button, live traffic and quick tests.
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _singBox = SingBox.instance;
  SingBoxServerConfig? _active;
  SingBoxPingResult? _ping;
  SingBoxNetworkQuality? _quality;
  bool _busy = false;
  StreamSubscription<SingBoxNetworkQuality>? _qualitySub;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _loadActive();
    // Re-render every second so the session timer moves.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _singBox.isConnected) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _qualitySub?.cancel();
    super.dispose();
  }

  Future<void> _loadActive() async {
    final active = await _singBox.getActiveServerConfig();
    if (mounted) setState(() => _active = active);
  }

  Future<void> _toggle(SingBoxConnectionStatus status) async {
    setState(() => _busy = true);
    try {
      if (status.isActive) {
        await _singBox.disconnect();
      } else {
        final active = await _singBox.getActiveServerConfig();
        if (active == null) {
          if (mounted) {
            showMessage(context, 'Add a server on the Servers tab first.');
          }
          return;
        }
        await _singBox.requestNotificationPermission();
        await _singBox.connectToServer(active);
      }
    } on SingBoxException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    } finally {
      await _loadActive();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _measurePing() async {
    setState(() => _ping = null);
    final ping = await _singBox.pingCurrentServer();
    if (mounted) setState(() => _ping = ping);
  }

  void _runSpeedTest() {
    _qualitySub?.cancel();
    setState(
      () => _quality = const SingBoxNetworkQuality(
        phase: SingBoxNetworkQualityPhase.idle,
      ),
    );
    _qualitySub = _singBox.runNetworkQualityTest().listen(
      (q) => setState(() => _quality = q),
      onError: (Object e) {
        if (!mounted) return;
        setState(() => _quality = null);
        showMessage(context, '$e', error: true);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<SingBoxConnectionState>(
      stream: _singBox.watchConnectionState(),
      initialData: _singBox.state,
      builder: (context, snapshot) {
        final state = snapshot.data ?? SingBoxConnectionState.initial;
        final connected = state.status == SingBoxConnectionStatus.connected;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _StatusCard(
              state: state,
              server: _active,
              busy: _busy || state.status.isTransitioning,
              onToggle: () => _toggle(state.status),
            ),
            if (connected) ...[
              const SizedBox(height: 12),
              const _TrafficCard(),
              const SizedBox(height: 12),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.timer_outlined),
                      title: const Text('Latency (URL test)'),
                      subtitle: Text(
                        _ping == null
                            ? 'Tap to measure'
                            : _ping!.success
                            ? '${_ping!.ping} ms via ${_ping!.tag}'
                            : _ping!.errorMessage ?? 'Failed',
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.refresh),
                        onPressed: _measurePing,
                      ),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.speed),
                      title: const Text('Speed test (network quality)'),
                      subtitle: Text(_qualityText()),
                      trailing: IconButton(
                        icon: const Icon(Icons.play_arrow),
                        onPressed: _runSpeedTest,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  String _qualityText() {
    final q = _quality;
    if (q == null) return 'Measures through the tunnel';
    final down = '${q.downloadMbps.toStringAsFixed(1)} Mbps';
    final up = '${q.uploadMbps.toStringAsFixed(1)} Mbps';
    final latency = q.idleLatency == null
        ? ''
        : ', ${q.idleLatency!.inMilliseconds} ms';
    return q.isFinal
        ? '↓ $down  ↑ $up$latency  (RPM ${q.downloadRpm}/${q.uploadRpm})'
        : '${q.phase.name}… ↓ $down  ↑ $up$latency';
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.state,
    required this.server,
    required this.busy,
    required this.onToggle,
  });

  final SingBoxConnectionState state;
  final SingBoxServerConfig? server;
  final bool busy;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final connected = state.status == SingBoxConnectionStatus.connected;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(
              connected ? Icons.shield : Icons.shield_outlined,
              size: 72,
              color: connected ? scheme.primary : scheme.outline,
            ),
            const SizedBox(height: 12),
            Text(
              state.status.name.toUpperCase(),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (connected) Text(formatDuration(state.duration)),
            const SizedBox(height: 4),
            Text(
              server == null
                  ? 'No server selected'
                  : '${server!.name} · ${server!.protocol}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (state.error != null) ...[
              const SizedBox(height: 8),
              Text(
                state.error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.error),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: busy ? null : onToggle,
              icon: Icon(state.status.isActive ? Icons.stop : Icons.power),
              label: Text(state.status.isActive ? 'Disconnect' : 'Connect'),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrafficCard extends StatelessWidget {
  const _TrafficCard();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<SingBoxConnectionStats>(
      stream: SingBox.instance.watchConnectionStats(),
      builder: (context, snapshot) {
        final s = snapshot.data ?? SingBoxConnectionStats.empty;
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    _Metric('↓ Download', formatSpeed(s.downloadSpeed)),
                    _Metric('↑ Upload', formatSpeed(s.uploadSpeed)),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _Metric('Received', formatBytes(s.downloadTotal)),
                    _Metric('Sent', formatBytes(s.uploadTotal)),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _Metric(
                      'Connections',
                      '${s.connectionsIn} in / ${s.connectionsOut} out',
                    ),
                    _Metric('Core memory', formatBytes(s.memory)),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          Text(value, style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
    );
  }
}
