/// Pure Dart sing-box 1.14 configuration toolkit.
///
/// * [SingBoxShareLink] parses share links (`vless://`, `vmess://`,
///   `trojan://`, `ss://`, `hysteria2://`, `tuic://`, …) and subscriptions
///   into [SingBoxOutbound]s and converts outbounds back to links.
/// * [SingBoxConfigBuilder] turns outbounds plus [SingBoxRoutingRules] into a
///   complete configuration (TUN inbound, DNS, routing, rule-sets) or patches
///   a user supplied configuration.
/// * [SingBoxDnsServer] converts DNS address strings into sing-box DNS server
///   objects and [SingBoxRuleSets] knows the remote geoip/geosite rule-sets.
library;

export 'config_builder.dart' show SingBoxConfigBuilder;
export 'config_options.dart'
    show
        SingBoxConfigLogLevel,
        SingBoxConfigOptions,
        SingBoxDnsOptions,
        SingBoxDnsStrategy,
        SingBoxInboundMode,
        SingBoxLocalProxy,
        SingBoxTunOptions,
        SingBoxTunStack;
export 'dns_server.dart' show SingBoxDnsServer;
export 'outbound.dart' show SingBoxOutbound;
export 'routing_rule.dart'
    show SingBoxRoutingRule, SingBoxRuleAction, SingBoxRuleNetwork;
export 'routing_rules.dart'
    show SingBoxIpVersion, SingBoxRoutingMode, SingBoxRoutingRules;
export 'rule_sets.dart' show SingBoxRuleSets;
export 'share_link.dart' show SingBoxShareLink;
