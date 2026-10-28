import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sing_box/sing_box.dart';

import 'format.dart';
import 'ui.dart';

/// Subscriptions, server profiles (import, select, connect) and live
/// outbound groups.
class ServersPage extends StatefulWidget {
  const ServersPage({super.key});

  @override
  State<ServersPage> createState() => _ServersPageState();
}

class _ServersPageState extends State<ServersPage> {
  final _singBox = SingBox.instance;
  List<SingBoxServerConfig> _servers = const [];
  List<SingBoxSubscription> _subscriptions = const [];
  String? _activeId;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final servers = await _singBox.getServerConfigs();
    final subscriptions = await _singBox.getSubscriptions();
    final active = await _singBox.getActiveServerConfig();
    if (!mounted) return;
    setState(() {
      _servers = servers;
      _subscriptions = subscriptions;
      _activeId = active?.id;
    });
  }

  Future<void> _selectFirstIfNone() async {
    if (await _singBox.getActiveServerConfig() != null) return;
    final servers = await _singBox.getServerConfigs();
    if (servers.isNotEmpty) {
      await _singBox.setActiveServerConfig(servers.first.id);
    }
  }

  /// An http(s) URL with a path is a subscription; `http://user:pass@host:port`
  /// without one is an HTTP proxy share link.
  static bool _isSubscriptionUrl(String text) {
    if (text.contains('\n')) return false;
    final uri = Uri.tryParse(text);
    return uri != null &&
        (uri.isScheme('http') || uri.isScheme('https')) &&
        uri.path.length > 1;
  }

  Future<void> _addSubscription([String? url]) async {
    url ??= await promptText(
      context,
      title: 'Subscription URL',
      hint: 'https://example.com/sub/…',
    );
    if (url == null || url.trim().isEmpty) return;
    try {
      final subscription = await _singBox.addSubscription(url.trim());
      if (mounted) {
        showMessage(
          context,
          'Added ${subscription.name}: '
          '${subscription.serverCount} server(s)',
        );
      }
      await _selectFirstIfNone();
    } on SingBoxSubscriptionException catch (e) {
      if (mounted) showMessage(context, 'Failed: ${e.message}', error: true);
    }
    await _reload();
  }

  Future<void> _updateSubscription(SingBoxSubscription subscription) async {
    try {
      final updated = await _singBox.updateSubscription(subscription.id);
      if (mounted) {
        showMessage(
          context,
          '${updated.name}: ${updated.serverCount} server(s)',
        );
      }
    } on SingBoxSubscriptionException catch (e) {
      if (mounted) showMessage(context, 'Failed: ${e.message}', error: true);
    }
    await _reload();
  }

  Future<void> _updateAllSubscriptions() async {
    final updated = await _singBox.updateSubscriptions();
    if (mounted) {
      showMessage(
        context,
        'Updated ${updated.length} of ${_subscriptions.length} subscription(s)',
        error: updated.length < _subscriptions.length,
      );
    }
    await _reload();
  }

  static String _subscriptionInfo(SingBoxSubscription subscription) {
    final used = subscription.used;
    final total = subscription.total;
    final expire = subscription.expire;
    return [
      '${subscription.serverCount} server(s)',
      if (used != null)
        total != null && total > 0
            ? '${formatBytes(used)} of ${formatBytes(total)}'
            : '${formatBytes(used)} used',
      if (expire != null)
        '${subscription.isExpired ? 'expired' : 'until'} '
            '${expire.toLocal().toString().split(' ').first}',
      if (subscription.lastError != null) 'error: ${subscription.lastError}',
    ].join(' · ');
  }

  Future<void> _import(String content) async {
    if (content.trim().isEmpty) return;
    try {
      final trimmed = content.trim();
      if (_isSubscriptionUrl(trimmed)) {
        await _addSubscription(trimmed);
        return;
      }
      if (trimmed.startsWith('{')) {
        final decoded = jsonDecode(trimmed) as Map<String, dynamic>;
        final isFull = decoded.containsKey('outbounds');
        final name = await promptText(context, title: 'Profile name') ?? '';
        final id = 'json-${DateTime.now().millisecondsSinceEpoch}';
        final server = isFull
            ? SingBoxServerConfig.fromFullConfig(
                trimmed,
                id: id,
                name: name.isEmpty ? 'Custom config' : name,
              )
            : SingBoxServerConfig.fromOutbound(
                decoded,
                id: id,
                name: name.isEmpty ? null : name,
              );
        await _singBox.addServerConfig(server);
        if (mounted) showMessage(context, 'Added ${server.name}');
      } else {
        final imported = await _singBox.importServerConfigs(trimmed);
        if (mounted) {
          showMessage(
            context,
            imported.isEmpty
                ? 'No supported links found'
                : 'Imported ${imported.length} server(s)',
            error: imported.isEmpty,
          );
        }
      }
      await _selectFirstIfNone();
    } on Object catch (e) {
      if (mounted) showMessage(context, 'Import failed: $e', error: true);
    }
    await _reload();
  }

  Future<void> _importFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    await _import(data?.text ?? '');
  }

  Future<void> _importManually() async {
    final text = await promptText(
      context,
      title: 'Share links, subscription or JSON',
      hint: 'vless://… / Clash YAML / {"type": "trojan", …}',
      maxLines: 6,
    );
    if (text != null) await _import(text);
  }

  Future<void> _connect(SingBoxServerConfig server) async {
    try {
      await _singBox.connectToServer(server);
    } on SingBoxException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    }
    await _reload();
  }

  Future<void> _connectAll() async {
    try {
      await _singBox.connectToServers(_servers, selectedId: _activeId);
      if (mounted) {
        showMessage(context, 'All servers loaded into the "proxy" selector');
      }
    } on SingBoxException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    }
  }

  Future<void> _showDetails(SingBoxServerConfig server) async {
    String text;
    try {
      text = const JsonEncoder.withIndent(
        '  ',
      ).convert(jsonDecode(server.config));
    } on FormatException {
      text = server.config;
    }
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(server.name),
        content: SingleChildScrollView(
          child: SelectableText(
            '${server.link ?? ''}\n\n$text',
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ),
        actions: [
          if (server.link != null)
            TextButton(
              onPressed: () =>
                  Clipboard.setData(ClipboardData(text: server.link!)),
              child: const Text('Copy link'),
            ),
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
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _importFromClipboard,
        icon: const Icon(Icons.content_paste),
        label: const Text('Import from clipboard'),
      ),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 96),
          children: [
            SectionHeader(
              'Subscriptions',
              trailing: Wrap(
                children: [
                  IconButton(
                    tooltip: 'Add a subscription URL',
                    icon: const Icon(Icons.add_link),
                    onPressed: _addSubscription,
                  ),
                  IconButton(
                    tooltip: 'Update all subscriptions',
                    icon: const Icon(Icons.sync),
                    onPressed: _subscriptions.isEmpty
                        ? null
                        : _updateAllSubscriptions,
                  ),
                ],
              ),
            ),
            for (final subscription in _subscriptions)
              ListTile(
                leading: const Icon(Icons.rss_feed),
                title: Text(subscription.name),
                subtitle: Text(_subscriptionInfo(subscription)),
                trailing: PopupMenuButton<String>(
                  onSelected: (action) async {
                    switch (action) {
                      case 'update':
                        await _updateSubscription(subscription);
                      case 'delete':
                        await _singBox.removeSubscription(subscription.id);
                        await _reload();
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'update', child: Text('Update')),
                    PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
              ),
            SectionHeader(
              'Profiles',
              trailing: Wrap(
                children: [
                  IconButton(
                    tooltip: 'Paste links or JSON',
                    icon: const Icon(Icons.add),
                    onPressed: _importManually,
                  ),
                  IconButton(
                    tooltip: 'Connect with all servers (selector + urltest)',
                    icon: const Icon(Icons.hub_outlined),
                    onPressed: _servers.isEmpty ? null : _connectAll,
                  ),
                ],
              ),
            ),
            if (_servers.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No servers yet. Copy a share link (vless://, vmess://, '
                  'trojan://, ss://, hysteria2://, tuic://…), a subscription '
                  'URL or a Clash YAML and tap "Import from clipboard".',
                  textAlign: TextAlign.center,
                ),
              ),
            RadioGroup<String>(
              groupValue: _activeId,
              onChanged: (id) async {
                await _singBox.setActiveServerConfig(id);
                await _reload();
              },
              child: Column(
                children: [
                  for (final server in _servers)
                    ListTile(
                      leading: Radio<String>(value: server.id),
                      title: Text(server.name),
                      subtitle: Text(
                        '${server.protocol} · ${server.server}:${server.port}',
                      ),
                      onTap: () => _showDetails(server),
                      trailing: PopupMenuButton<String>(
                        onSelected: (action) async {
                          switch (action) {
                            case 'connect':
                              await _connect(server);
                            case 'delete':
                              await _singBox.removeServerConfig(server.id);
                              await _reload();
                          }
                        },
                        itemBuilder: (context) => const [
                          PopupMenuItem(
                            value: 'connect',
                            child: Text('Connect'),
                          ),
                          PopupMenuItem(value: 'delete', child: Text('Delete')),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const _GroupsSection(),
          ],
        ),
      ),
    );
  }
}

class _GroupsSection extends StatelessWidget {
  const _GroupsSection();

  @override
  Widget build(BuildContext context) {
    final singBox = SingBox.instance;
    return StreamBuilder<SingBoxConnectionStatus>(
      stream: singBox.watchConnectionStatus(),
      initialData: singBox.status,
      builder: (context, status) {
        if (status.data != SingBoxConnectionStatus.connected) {
          return const SizedBox.shrink();
        }
        return StreamBuilder<List<SingBoxOutboundGroup>>(
          stream: singBox.watchGroups(),
          builder: (context, snapshot) {
            final groups = snapshot.data ?? const [];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final group in groups) ...[
                  SectionHeader(
                    'Group "${group.tag}" (${group.type})',
                    trailing: IconButton(
                      tooltip: 'URL test',
                      icon: const Icon(Icons.network_ping),
                      onPressed: () => singBox.urlTest(group.tag),
                    ),
                  ),
                  for (final item in group.items)
                    ListTile(
                      dense: true,
                      selected: item.tag == group.selected,
                      leading: Icon(
                        item.tag == group.selected
                            ? Icons.check_circle
                            : Icons.circle_outlined,
                      ),
                      title: Text(item.tag),
                      subtitle: Text(item.type),
                      trailing: Text(
                        item.urlTestDelay != null
                            ? '${item.urlTestDelay} ms'
                            : item.urlTestFailed
                            ? 'timeout'
                            : '—',
                      ),
                      onTap: group.selectable
                          ? () => singBox.selectOutbound(group.tag, item.tag)
                          : null,
                    ),
                ],
              ],
            );
          },
        );
      },
    );
  }
}
