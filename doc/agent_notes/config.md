# Config module agent notes (lib/src/config/**, test/config/**)

Status: IN PROGRESS — writing code. Done on disk: config.dart (barrel), config_options.dart, routing_rules.dart,
rule_sets.dart, dns_server.dart, outbound.dart, internal/json_utils.dart, internal/uri_parts.dart.
TODO: share_link.dart (+internal/link_parser.dart, link_writer.dart, subscription.dart), config_builder.dart, tests.

## Binary
- sing-box CLI (v1.14 source checkout, tags with_gvisor,with_quic,with_wireguard,with_utls,with_clash_api):
  `/private/tmp/claude-501/-Users-qusadprod-projects-sing-box--claude-worktrees-singbox-flutter-plugin-review-22aa2f/74d8003d-46eb-43d7-aed2-deade4eeec8f/scratchpad/bin/sing-box`
- Run checks: `SING_BOX_BIN=<that path> ~/dev/flutter/bin/flutter test test/config`

## Planned files
- `lib/src/config/config.dart` — barrel (facade imports only this)
- `lib/src/config/config_options.dart` — enums SingBoxConfigLogLevel, SingBoxTunStack, SingBoxDnsStrategy; SingBoxTunOptions, SingBoxDnsOptions, SingBoxConfigOptions
- `lib/src/config/routing_rules.dart` — SingBoxRoutingRules (toMap/fromMap/copyWith/==)
- `lib/src/config/rule_sets.dart` — SingBoxRuleSets (geoip/geosite URLs, curated country catalog)
- `lib/src/config/dns_server.dart` — SingBoxDnsServer.parse(address, tag:, detour:)
- `lib/src/config/outbound.dart` — SingBoxOutbound
- `lib/src/config/share_link.dart` — SingBoxShareLink (parse/tryParse/isSupported/parseSubscription/toLink)
- `lib/src/config/config_builder.dart` — SingBoxConfigBuilder (build/buildFromJson/apply), constants proxyTag='proxy', autoTag='auto', directTag='direct'
- `lib/src/config/internal/*` — private helpers (not exported)

## Key findings from sing-box 1.14 source (drive the design)
- DNS servers dial with DirectResolver: a hostname server WITHOUT detour needs explicit `domain_resolver`
  (no fallback to route.default_domain_resolver). With `detour: proxy` and no domain_resolver the proxy resolves it (no leak).
- `detour` to an *empty direct* outbound fails lazily at first dial ("detour to an empty direct outbound makes no sense")
  — `sing-box check` does NOT catch it. Never emit `detour: "direct"` for DNS servers / http clients.
- Remote rule-set `download_detour` deprecated in 1.14; implicit default HTTP client deprecated. Use top-level
  `http_clients: [{tag}]` (+ `detour: proxy` when downloading via proxy) and reference it from each rule-set.
- Initial remote rule-set download failure aborts startup -> only reference rule-sets that exist.
  geoip-<cc> exists for 238 countries; geosite-<cc> is a COUNTRY only for `cn` (geosite-vk/ok/rt are brands!).
  Curated: cn->geosite-cn, ru->geosite-category-ru, ir->geosite-category-ir. geosite-category-ads-all exists.
- Do not reference geoip (ip-only) rule-sets in DNS rules (1.14 deprecation / rejection).
- tun 1.14: connections to the tun DNS address are hijacked automatically; we still add a hijack-dns rule (protocol dns OR port 53).
- Clash mode manager exists in libbox regardless; clash_api without external_controller does not listen.
- Endpoints (wireguard) can be referenced by selector/urltest tags.

## Design decisions (implemented)
- DNS tags: dns-remote (detour proxy, final), dns-direct (route.default_domain_resolver), dns-fakeip, dns-local (bootstrap
  for a hostname-based direct server), custom rules.dnsServers -> dns-remote, dns-remote-2...
- Rule-sets: one remote binary def per tag, http_client = top-level http_clients tag 'rule-set-download'
  (no detour when ruleSetDownloadDetour == direct). URL templates with {tag} in SingBoxConfigOptions.
- Countries: SingBoxRuleSets.countryRuleSets(cc) -> curated geosite (cn, ru->category-ru, ir->category-ir) + geoip-cc.
- Blocked domains in DNS: predefined NXDOMAIN.

## Next steps
1. Write lib files + barrel. 2. Tests. 3. format/analyze/test + sing-box check. 4. Final report.
