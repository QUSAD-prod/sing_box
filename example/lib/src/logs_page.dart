import 'package:flutter/material.dart';
import 'package:sing_box/sing_box.dart';

/// Live sing-box core log with a level filter.
class LogsPage extends StatefulWidget {
  const LogsPage({super.key});

  @override
  State<LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends State<LogsPage> {
  SingBoxLogLevel _minLevel = SingBoxLogLevel.info;
  final _stream = SingBox.instance.watchLogBuffer(maxEntries: 2000);

  Color? _color(BuildContext context, SingBoxLogLevel level) {
    final scheme = Theme.of(context).colorScheme;
    if (level.isAtLeast(SingBoxLogLevel.error)) return scheme.error;
    if (level == SingBoxLogLevel.warn) return Colors.orange;
    if (level.value >= SingBoxLogLevel.debug.value) return scheme.outline;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            children: [
              const Text('Level'),
              const SizedBox(width: 12),
              DropdownButton<SingBoxLogLevel>(
                value: _minLevel,
                items: [
                  for (final level in SingBoxLogLevel.values)
                    DropdownMenuItem(value: level, child: Text(level.name)),
                ],
                onChanged: (v) => setState(() => _minLevel = v ?? _minLevel),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Clear',
                icon: const Icon(Icons.delete_sweep_outlined),
                onPressed: () => SingBox.instance.clearLogs().catchError((_) {}),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: StreamBuilder<List<SingBoxLogEntry>>(
            stream: _stream,
            builder: (context, snapshot) {
              final entries = (snapshot.data ?? const [])
                  .where((e) => e.level.isAtLeast(_minLevel))
                  .toList()
                  .reversed
                  .toList();
              if (entries.isEmpty) {
                return const Center(
                  child: Text('Logs appear while the VPN is running'),
                );
              }
              return ListView.builder(
                itemCount: entries.length,
                itemBuilder: (context, index) {
                  final entry = entries[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 2,
                    ),
                    child: Text(
                      entry.plainMessage,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        color: _color(context, entry.level),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
