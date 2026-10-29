import 'internal/json_utils.dart';

/// What a [SingBoxRoutingRule] does with the matching traffic.
enum SingBoxRuleAction {
  /// Connect through the proxy (the main `proxy` selector) and resolve
  /// names with the remote DNS server.
  proxy,

  /// Connect directly and resolve names with the direct DNS server.
  direct,

  /// Reject the connection (`action: reject`); names are answered with
  /// `NXDOMAIN`.
  block;

  /// Returns the value whose [name] equals [name] (case-insensitive), or
  /// `null` when nothing matches.
  static SingBoxRuleAction? tryParse(String? name) {
    final normalized = name?.trim().toLowerCase();
    for (final value in values) {
      if (value.name == normalized) return value;
    }
    return null;
  }
}

/// Transport protocol matched by [SingBoxRoutingRule.network].
enum SingBoxRuleNetwork {
  /// TCP connections.
  tcp,

  /// UDP packets.
  udp;

  /// Returns the value whose [name] equals [name] (case-insensitive), or
  /// `null` when nothing matches.
  static SingBoxRuleNetwork? tryParse(String? name) {
    final normalized = name?.trim().toLowerCase();
    for (final value in values) {
      if (value.name == normalized) return value;
    }
    return null;
  }
}

/// A user defined routing rule of `SingBoxRoutingRules.customRules`.
///
/// Custom rules are evaluated in list order, after the blocked lists and the
/// Clash modes but before the proxy lists, the LAN and the bypass lists, so
/// they override the presets. The first matching rule wins.
///
/// Within one rule the destination conditions ([domains], [domainSuffixes],
/// [domainKeywords], [domainRegexes], [ipCidrs], [ruleSets]) match when
/// **any** of them matches; [ports], [packages], [network] and [protocols]
/// must match **as well**. A rule without any condition is ignored, and so
/// are invalid entries.
///
/// | Field | sing-box |
/// |-------|----------|
/// | [domains] | `domain` |
/// | [domainSuffixes] | `domain_suffix` |
/// | [domainKeywords] | `domain_keyword` |
/// | [domainRegexes] | `domain_regex` (Go RE2 syntax) |
/// | [ipCidrs] | `ip_cidr` |
/// | [ports] | `port` / `port_range` |
/// | [packages] | `package_name` (Android) |
/// | [ruleSets] | `rule_set` (remote rule-sets) |
/// | [network] | `network` |
/// | [protocols] | `protocol` (needs `SingBoxConfigOptions.sniff`) |
///
/// ```dart
/// const rules = SingBoxRoutingRules(
///   customRules: [
///     SingBoxRoutingRule(
///       name: 'Work',
///       action: SingBoxRuleAction.direct,
///       domainSuffixes: ['corp.example.com'],
///       ipCidrs: ['10.20.0.0/16'],
///     ),
///     SingBoxRoutingRule(
///       action: SingBoxRuleAction.proxy,
///       ruleSets: ['geosite-youtube', 'https://example.com/my-list.srs'],
///     ),
///     SingBoxRoutingRule(
///       action: SingBoxRuleAction.block,
///       ports: ['25', '6881-6889'],
///       network: SingBoxRuleNetwork.tcp,
///     ),
///   ],
/// );
/// ```
class SingBoxRoutingRule {
  /// Creates a rule. Every condition defaults to empty.
  const SingBoxRoutingRule({
    required this.action,
    this.name = '',
    this.enabled = true,
    this.domains = const [],
    this.domainSuffixes = const [],
    this.domainKeywords = const [],
    this.domainRegexes = const [],
    this.ipCidrs = const [],
    this.ports = const [],
    this.packages = const [],
    this.ruleSets = const [],
    this.network,
    this.protocols = const [],
  });

  /// Sniffed protocols that sing-box can match in [protocols].
  static const knownProtocols = {
    'http',
    'tls',
    'quic',
    'stun',
    'dtls',
    'bittorrent',
    'ssh',
    'rdp',
    'ntp',
    'dns',
  };

  /// What happens to the matching traffic.
  final SingBoxRuleAction action;

  /// Optional label shown in the app; not used for matching.
  final String name;

  /// Whether the rule is applied. Disabled rules are kept but skipped.
  final bool enabled;

  /// Exact domain names.
  final List<String> domains;

  /// Domain suffixes: `example.com` also matches `www.example.com`.
  final List<String> domainSuffixes;

  /// Keywords contained in the domain name.
  final List<String> domainKeywords;

  /// Regular expressions matched against the domain name (Go RE2 syntax).
  final List<String> domainRegexes;

  /// Destination subnets (CIDR) or IP addresses.
  final List<String> ipCidrs;

  /// Destination ports (`443`) or port ranges (`1000-2000`, `1000:2000`).
  final List<String> ports;

  /// Android package names of the apps making the connection.
  final List<String> packages;

  /// Rule-sets: tags of the SagerNet geosite/geoip lists (`geosite-youtube`,
  /// `geoip-us`, see `SingBoxRuleSets`) or `https://` URLs of binary (`.srs`)
  /// or source (`.json`) rule-sets.
  final List<String> ruleSets;

  /// Transport protocol, or `null` for both.
  final SingBoxRuleNetwork? network;

  /// Sniffed protocols (see [knownProtocols]), e.g. `quic`, `bittorrent`.
  final List<String> protocols;

  /// Converts the rule to a JSON-safe map whose keys are the field names.
  Map<String, dynamic> toMap() => {
    'action': action.name,
    if (name.isNotEmpty) 'name': name,
    if (!enabled) 'enabled': false,
    if (domains.isNotEmpty) 'domains': List<String>.of(domains),
    if (domainSuffixes.isNotEmpty)
      'domainSuffixes': List<String>.of(domainSuffixes),
    if (domainKeywords.isNotEmpty)
      'domainKeywords': List<String>.of(domainKeywords),
    if (domainRegexes.isNotEmpty)
      'domainRegexes': List<String>.of(domainRegexes),
    if (ipCidrs.isNotEmpty) 'ipCidrs': List<String>.of(ipCidrs),
    if (ports.isNotEmpty) 'ports': List<String>.of(ports),
    if (packages.isNotEmpty) 'packages': List<String>.of(packages),
    if (ruleSets.isNotEmpty) 'ruleSets': List<String>.of(ruleSets),
    if (network != null) 'network': network!.name,
    if (protocols.isNotEmpty) 'protocols': List<String>.of(protocols),
  };

  /// Creates a rule from a map produced by [toMap], or returns `null` when
  /// the map has no valid `action`. Unknown keys are ignored and list items
  /// that are not strings are dropped; ports may also be numbers.
  static SingBoxRoutingRule? tryFromMap(Map<dynamic, dynamic> map) {
    final action = SingBoxRuleAction.tryParse(readString(map['action']));
    if (action == null) return null;
    final ports = map['ports'];
    return SingBoxRoutingRule(
      action: action,
      name: readString(map['name']) ?? '',
      enabled: readBool(map['enabled']) ?? true,
      domains: readStringList(map['domains']),
      domainSuffixes: readStringList(map['domainSuffixes']),
      domainKeywords: readStringList(map['domainKeywords']),
      domainRegexes: readStringList(map['domainRegexes']),
      ipCidrs: readStringList(map['ipCidrs']),
      ports: [
        if (ports is List)
          for (final port in ports)
            if (port is String || port is int) '$port',
      ],
      packages: readStringList(map['packages']),
      ruleSets: readStringList(map['ruleSets']),
      network: SingBoxRuleNetwork.tryParse(readString(map['network'])),
      protocols: readStringList(map['protocols']),
    );
  }

  /// Returns a copy with the given fields replaced. Pass
  /// `clearNetwork: true` to remove [network].
  SingBoxRoutingRule copyWith({
    SingBoxRuleAction? action,
    String? name,
    bool? enabled,
    List<String>? domains,
    List<String>? domainSuffixes,
    List<String>? domainKeywords,
    List<String>? domainRegexes,
    List<String>? ipCidrs,
    List<String>? ports,
    List<String>? packages,
    List<String>? ruleSets,
    SingBoxRuleNetwork? network,
    bool clearNetwork = false,
    List<String>? protocols,
  }) {
    return SingBoxRoutingRule(
      action: action ?? this.action,
      name: name ?? this.name,
      enabled: enabled ?? this.enabled,
      domains: domains ?? this.domains,
      domainSuffixes: domainSuffixes ?? this.domainSuffixes,
      domainKeywords: domainKeywords ?? this.domainKeywords,
      domainRegexes: domainRegexes ?? this.domainRegexes,
      ipCidrs: ipCidrs ?? this.ipCidrs,
      ports: ports ?? this.ports,
      packages: packages ?? this.packages,
      ruleSets: ruleSets ?? this.ruleSets,
      network: clearNetwork ? null : network ?? this.network,
      protocols: protocols ?? this.protocols,
    );
  }

  static bool _listEquals(List<String> a, List<String> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  bool operator ==(Object other) =>
      other is SingBoxRoutingRule &&
      other.action == action &&
      other.name == name &&
      other.enabled == enabled &&
      _listEquals(other.domains, domains) &&
      _listEquals(other.domainSuffixes, domainSuffixes) &&
      _listEquals(other.domainKeywords, domainKeywords) &&
      _listEquals(other.domainRegexes, domainRegexes) &&
      _listEquals(other.ipCidrs, ipCidrs) &&
      _listEquals(other.ports, ports) &&
      _listEquals(other.packages, packages) &&
      _listEquals(other.ruleSets, ruleSets) &&
      other.network == network &&
      _listEquals(other.protocols, protocols);

  @override
  int get hashCode => Object.hash(
    action,
    name,
    enabled,
    Object.hashAll(domains),
    Object.hashAll(domainSuffixes),
    Object.hashAll(domainKeywords),
    Object.hashAll(domainRegexes),
    Object.hashAll(ipCidrs),
    Object.hashAll(ports),
    Object.hashAll(packages),
    Object.hashAll(ruleSets),
    network,
    Object.hashAll(protocols),
  );

  @override
  String toString() => 'SingBoxRoutingRule(${toMap()})';
}
