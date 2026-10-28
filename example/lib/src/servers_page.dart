import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sing_box/sing_box.dart';

import 'ui.dart';

/// Server profiles (import, select, connect) and live outbound groups.
class ServersPage extends StatefulWidget {
  const ServersPage({super.key});

  @override
  State<ServersPage> createState() => _ServersPageState();
}

class _ServersPageState extends State<ServersPage> {
  final _singBox = SingBox.instance;
  List<SingBoxServerConfig> _servers = const [];
  String? _activeId;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final servers = await _singBox.getServerConfigs();
    final active = await _singBox.getActiveServerConfig();
    if (!mounted) return;
    setState(() {
      _servers = servers;
      _activeId = active?.id;
    });
  }

  Future<void> _import(String content) async {
    if (content.trim().isEmpty) return;
    try {
      final trimmed = content.trim();
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
      if (_activeId == null && (await _singBox.getServerConfigs()).isNotEmpty) {
        await _singBox.setActiveServerConfig(
          (await _singBox.getServerConfigs()).first.id,
        );
      }
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
      hint: 'vless://… / ss://… / {"type": "trojan", …}',
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
                  'trojan://, ss://, hysteria2://, tuic://…) or a subscription '
                  'and tap "Import from clipboard".',
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
