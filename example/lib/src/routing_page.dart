import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sing_box/sing_box.dart';

import 'ui.dart';

/// Routing mode, proxy / bypass / block lists, custom rules, per-app
/// routing, DNS servers and the downloaded rule-sets.
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
  List<SingBoxRuleSetStatus> _ruleSets = const [];
  bool _updatingRuleSets = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final rules = await _singBox.getRoutingRules();
    final ruleSets = await _singBox.getRuleSets();
    if (mounted) {
      setState(() {
        _rules = rules;
        _ruleSets = ruleSets;
      });
    }
  }

  Future<void> _updateRuleSets() async {
    setState(() => _updatingRuleSets = true);
    try {
      final statuses = await _singBox.updateRuleSets(force: true);
      final failed = statuses.where((s) => s.lastError != null).length;
      if (mounted) {
        showMessage(
          context,
          failed == 0
              ? 'Rule-sets updated'
              : '$failed of ${statuses.length} rule-sets failed',
          error: failed > 0,
        );
      }
    } finally {
      if (mounted) setState(() => _updatingRuleSets = false);
      await _reload();
    }
  }

  Future<void> _exportRules() async {
    await Clipboard.setData(
      ClipboardData(text: await _singBox.exportRoutingRules()),
    );
    if (mounted) showMessage(context, 'Routing rules copied as JSON');
  }

  Future<void> _importRules() async {
    final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    if (text == null || text.trim().isEmpty) return;
    try {
      await _singBox.importRoutingRules(text);
      if (mounted) showMessage(context, 'Routing rules imported');
    } on SingBoxException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    }
    await _reload();
  }

  /// Comma or whitespace separated values of [text].
  static List<String> _split(String text) =>
      text.split(RegExp(r'[,\s]+')).where((e) => e.isNotEmpty).toList();

  Future<void> _addCustomRule() async {
    var action = SingBoxRuleAction.proxy;
    final domains = TextEditingController();
    final cidrs = TextEditingController();
    final ruleSets = TextEditingController();
    final rule = await showDialog<SingBoxRoutingRule>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Custom rule'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SegmentedButton<SingBoxRuleAction>(
                  segments: const [
                    ButtonSegment(
                      value: SingBoxRuleAction.proxy,
                      label: Text('Proxy'),
                    ),
                    ButtonSegment(
                      value: SingBoxRuleAction.direct,
                      label: Text('Direct'),
                    ),
                    ButtonSegment(
                      value: SingBoxRuleAction.block,
                      label: Text('Block'),
                    ),
                  ],
                  selected: {action},
                  onSelectionChanged: (v) =>
                      setDialogState(() => action = v.single),
                ),
                TextField(
                  controller: domains,
                  decoration: const InputDecoration(
                    labelText: 'Domain suffixes',
                    hintText: 'example.com, example.org',
                  ),
                ),
                TextField(
                  controller: cidrs,
                  decoration: const InputDecoration(
                    labelText: 'IP addresses / CIDRs',
                    hintText: '10.0.0.0/8',
                  ),
                ),
                TextField(
                  controller: ruleSets,
                  decoration: const InputDecoration(
                    labelText: 'Rule-sets (tags or URLs)',
                    hintText: 'geosite-youtube, https://…/list.srs',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                context,
                SingBoxRoutingRule(
                  action: action,
                  domainSuffixes: _split(domains.text),
                  ipCidrs: _split(cidrs.text),
                  ruleSets: _split(ruleSets.text),
                ),
              ),
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
    if (rule == null) return;
    if (rule.domainSuffixes.isEmpty &&
        rule.ipCidrs.isEmpty &&
        rule.ruleSets.isEmpty) {
      if (mounted) {
        showMessage(context, 'The rule has no condition', error: true);
      }
      return;
    }
    await _singBox.setCustomRules([..._rules.customRules, rule]);
    await _reload();
  }

  Future<void> _removeCustomRule(int index) async {
    final rules = [..._rules.customRules]..removeAt(index);
    await _singBox.setCustomRules(rules);
    await _reload();
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
        if (values.isEmpty) const ListTile(dense: true, title: Text('Empty')),
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
          ListTile(
            title: const Text('Unmatched traffic'),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: SegmentedButton<SingBoxRoutingMode>(
                segments: const [
                  ButtonSegment(
                    value: SingBoxRoutingMode.proxyAll,
                    label: Text('Through VPN'),
                  ),
                  ButtonSegment(
                    value: SingBoxRoutingMode.proxyListed,
                    label: Text('Direct (only lists via VPN)'),
                  ),
                ],
                selected: {_rules.mode},
                onSelectionChanged: (v) async {
                  await _singBox.setRoutingMode(v.single);
                  await _reload();
                },
              ),
            ),
          ),
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
          SwitchListTile(
            title: const Text('Block QUIC'),
            subtitle: const Text('Apps fall back to TCP (HTTP/2)'),
            value: _rules.blockQuic,
            onChanged: (v) => _update((r) => r.copyWith(blockQuic: v)),
          ),
          SwitchListTile(
            title: const Text('BitTorrent directly'),
            subtitle: const Text('Never through the VPN'),
            value: _rules.bittorrentDirect,
            onChanged: (v) => _update((r) => r.copyWith(bittorrentDirect: v)),
          ),
          ListTile(
            title: const Text('IP version'),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: SegmentedButton<SingBoxIpVersion>(
                segments: const [
                  ButtonSegment(
                    value: SingBoxIpVersion.dual,
                    label: Text('IPv4 + IPv6'),
                  ),
                  ButtonSegment(
                    value: SingBoxIpVersion.ipv4,
                    label: Text('IPv4'),
                  ),
                  ButtonSegment(
                    value: SingBoxIpVersion.ipv6,
                    label: Text('IPv6'),
                  ),
                ],
                selected: {_rules.ipVersion},
                onSelectionChanged: (v) async {
                  await _singBox.setIpVersion(v.single);
                  await _reload();
                },
              ),
            ),
          ),
          _list(
            title: 'Through VPN: blocked in countries',
            hint: 'ru or cn',
            values: _rules.blockedInCountries,
            note:
                'Sites blocked in these countries always use the VPN '
                '(ru: runetfreedom lists, cn: sites outside China).',
            add: (v) async {
              if (!SingBoxRuleSets.isSupportedBlockedCountry(v)) return false;
              return _singBox.updateRoutingRules(
                (r) => r.copyWith(
                  blockedInCountries: {
                    ...r.blockedInCountries,
                    v.trim().toLowerCase(),
                  }.toList(),
                ),
              );
            },
            remove: (v) => _singBox.updateRoutingRules(
              (r) => r.copyWith(
                blockedInCountries: r.blockedInCountries
                    .where((c) => c != v)
                    .toList(),
              ),
            ),
          ),
          _list(
            title: 'Through VPN: domains',
            hint: 'example.org',
            values: _rules.proxyDomains,
            add: _singBox.addProxyDomain,
            remove: _singBox.removeProxyDomain,
          ),
          _list(
            title: 'Through VPN: subnets',
            hint: '203.0.113.0/24',
            values: _rules.proxySubnets,
            add: _singBox.addProxySubnet,
            remove: _singBox.removeProxySubnet,
          ),
          _list(
            title: 'Bypass countries',
            hint: 'ISO code, e.g. ru',
            values: _rules.bypassCountries,
            note:
                'Sites and IPs of these countries are reached directly '
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
                bypassCountries: r.bypassCountries
                    .where((c) => c != v)
                    .toList(),
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
            note:
                androidOnly ?? 'Ignored while "Only these apps" is not empty.',
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
          SectionHeader(
            'Custom rules (in order)',
            trailing: IconButton(
              icon: const Icon(Icons.add),
              onPressed: _addCustomRule,
            ),
          ),
          if (_rules.customRules.isEmpty)
            const ListTile(dense: true, title: Text('Empty')),
          for (final (index, rule) in _rules.customRules.indexed)
            ListTile(
              dense: true,
              leading: Text('${index + 1}'),
              title: Text(
                [
                  ...rule.domainSuffixes,
                  ...rule.ipCidrs,
                  ...rule.ruleSets,
                ].join(', '),
              ),
              subtitle: Text(rule.action.name),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _removeCustomRule(index),
              ),
            ),
          SectionHeader(
            'Rule-sets',
            trailing: _updatingRuleSets
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : IconButton(
                    icon: const Icon(Icons.refresh),
                    tooltip: 'Download again',
                    onPressed: _updateRuleSets,
                  ),
          ),
          if (_ruleSets.isEmpty)
            const ListTile(dense: true, title: Text('None downloaded yet')),
          for (final ruleSet in _ruleSets)
            ListTile(
              dense: true,
              leading: Icon(
                ruleSet.isAvailable
                    ? Icons.check_circle_outline
                    : Icons.error_outline,
              ),
              title: Text(ruleSet.tag),
              subtitle: Text(
                ruleSet.lastError ??
                    '${((ruleSet.size ?? 0) / 1024).toStringAsFixed(1)} KB, '
                        '${ruleSet.updatedAt}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          const SectionHeader('Backup'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.copy),
                  label: const Text('Export JSON'),
                  onPressed: _exportRules,
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.paste),
                  label: const Text('Import from clipboard'),
                  onPressed: _importRules,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
