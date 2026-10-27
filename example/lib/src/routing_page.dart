import 'dart:io';

import 'package:flutter/material.dart';
import 'package:sing_box/sing_box.dart';

import 'ui.dart';

/// Bypass / block lists, per-app routing and DNS servers.
///
/// Changes are persisted by the plugin and applied to the running tunnel
/// immediately (see `SingBox.reloadOnRulesChange`).
class RoutingPage extends StatefulWidget {
  const RoutingPage({super.key});

  @override
  State<RoutingPage> createState() => _RoutingPageState();
}

class _RoutingPageState extends State<RoutingPage> {
  final _singBox = SingBox.instance;
  SingBoxRoutingRules _rules = const SingBoxRoutingRules();

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final rules = await _singBox.getRoutingRules();
    if (mounted) setState(() => _rules = rules);
  }

  Future<void> _update(
    SingBoxRoutingRules Function(SingBoxRoutingRules r) change,
  ) async {
    await _singBox.updateRoutingRules(change);
    await _reload();
  }

  Future<void> _add(
    String title,
    String hint,
    Future<bool> Function(String value) add,
  ) async {
    final value = await promptText(context, title: title, hint: hint);
    if (value == null || value.isEmpty) return;
    final added = await add(value);
    if (!added && mounted) {
      showMessage(context, 'Invalid or duplicate value: $value', error: true);
    }
    await _reload();
  }

  Widget _list({
    required String title,
    required String hint,
    required List<String> values,
    required Future<bool> Function(String) add,
    required Future<bool> Function(String) remove,
    String? note,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title,
          trailing: IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _add(title, hint, add),
          ),
        ),
        if (note != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(note, style: Theme.of(context).textTheme.bodySmall),
          ),
        if (values.isEmpty)
          const ListTile(dense: true, title: Text('Empty')),
        for (final value in values)
          ListTile(
            dense: true,
            title: Text(value),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                await remove(value);
                await _reload();
              },
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final androidOnly = Platform.isAndroid
        ? null
        : 'Per-app routing is only available on Android.';
    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          const SectionHeader('General'),
          SwitchListTile(
            title: const Text('Bypass LAN'),
            subtitle: const Text('Private networks go directly'),
            value: _rules.bypassLan,
            onChanged: (v) => _update((r) => r.copyWith(bypassLan: v)),
          ),
          SwitchListTile(
            title: const Text('Block ads'),
            subtitle: const Text('geosite-category-ads-all rule-set'),
            value: _rules.blockAds,
            onChanged: (v) => _update((r) => r.copyWith(blockAds: v)),
          ),
          _list(
            title: 'Bypass countries',
            hint: 'ISO code, e.g. ru',
            values: _rules.bypassCountries,
            note: 'Sites and IPs of these countries are reached directly '
                '(geoip/geosite rule-sets).',
            add: (v) => _singBox.updateRoutingRules(
              (r) => r.copyWith(
                bypassCountries: {
                  ...r.bypassCountries,
                  v.toLowerCase(),
                }.toList(),
              ),
            ),
            remove: (v) => _singBox.updateRoutingRules(
              (r) => r.copyWith(
                bypassCountries: r.bypassCountries.where((c) => c != v).toList(),
              ),
            ),
          ),
          _list(
            title: 'Bypass domains',
            hint: 'example.com',
            values: _rules.bypassDomains,
            add: _singBox.addDomainToBypass,
            remove: _singBox.removeDomainFromBypass,
          ),
          _list(
            title: 'Bypass subnets',
            hint: '192.168.0.0/16',
            values: _rules.bypassSubnets,
            add: _singBox.addSubnetToBypass,
            remove: _singBox.removeSubnetFromBypass,
          ),
          _list(
            title: 'Blocked domains',
            hint: 'ads.example.com',
            values: _rules.blockedDomains,
            add: _singBox.addBlockedDomain,
            remove: _singBox.removeBlockedDomain,
          ),
          _list(
            title: 'Bypass apps',
            hint: 'com.example.app',
            values: _rules.bypassApps,
            note: androidOnly ?? 'Ignored while "Only these apps" is not empty.',
            add: _singBox.addAppToBypass,
            remove: _singBox.removeAppFromBypass,
          ),
          _list(
            title: 'Only these apps use the VPN',
            hint: 'org.telegram.messenger',
            values: _rules.proxyApps,
            note: androidOnly,
            add: (v) async {
              if (!SingBoxValidators.isPackageName(v)) return false;
              await _singBox.setProxyApps({..._rules.proxyApps, v}.toList());
              return true;
            },
            remove: (v) async {
              await _singBox.setProxyApps(
                _rules.proxyApps.where((a) => a != v).toList(),
              );
              return true;
            },
          ),
          _list(
            title: 'Blocked apps',
            hint: 'com.example.tracker',
            values: _rules.blockedApps,
            note: androidOnly,
            add: _singBox.addBlockedApp,
            remove: _singBox.removeBlockedApp,
          ),
          _list(
            title: 'DNS servers',
            hint: 'https://1.1.1.1/dns-query, tls://8.8.8.8, 9.9.9.9',
            values: _rules.dnsServers,
            note: 'Empty = default (DNS over HTTPS through the proxy).',
            add: _singBox.addDnsServer,
            remove: _singBox.removeDnsServer,
          ),
        ],
      ),
    );
  }
}
