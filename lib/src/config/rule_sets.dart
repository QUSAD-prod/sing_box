import 'config_options.dart';
import 'internal/json_utils.dart';

/// Catalog of the remote binary rule-sets that `SingBoxConfigBuilder`
/// references: the ones published by SagerNet
/// ([sing-geoip](https://github.com/SagerNet/sing-geoip) and
/// [sing-geosite](https://github.com/SagerNet/sing-geosite), branch
/// `rule-set`) plus the Russian lists of
/// [runetfreedom/russia-v2ray-rules-dat](https://github.com/runetfreedom/russia-v2ray-rules-dat)
/// (branch `release`, updated every few hours) in [thirdPartyUrls].
///
/// sing-box aborts startup when a remote rule-set cannot be downloaded the
/// first time, so only rule-sets known to exist are ever referenced:
///
/// * `geoip-<cc>` exists for every code in [geoipCountryCodes] (238
///   countries and territories);
/// * geosite lists are *not* published per country (e.g. `geosite-ru` does
///   not exist; `geosite-vk` is the VK brand). Curated country domain lists
///   are mapped in [geositeCountryTags] (`cn`, `ru`, `ir`);
/// * lists of resources blocked in a country are mapped in
///   [blockedCountryTags] (`ru`, `cn`).
///
/// ```dart
/// SingBoxRuleSets.countryRuleSets('RU');
/// // ['geosite-category-ru', 'geosite-ru-available-only-inside', 'geoip-ru']
/// SingBoxRuleSets.blockedRuleSets('ru');
/// // ['geosite-ru-blocked', 'geoip-ru-blocked']
/// SingBoxRuleSets.url('geoip-ru');
/// // 'https://raw.githubusercontent.com/SagerNet/sing-geoip/rule-set/geoip-ru.srs'
/// ```
abstract final class SingBoxRuleSets {
  /// Tag of the advertising domain list (`geosite-category-ads-all`).
  static const adsTag = 'geosite-category-ads-all';

  /// Country codes with a published `geoip-<cc>` rule-set.
  static const geoipCountryCodes = <String>{
    'ad', 'ae', 'af', 'ag', 'ai', 'al', 'am', 'ao', 'aq', 'ar', 'as', 'at', //
    'au', 'aw', 'ax', 'az', 'ba', 'bb', 'bd', 'be', 'bf', 'bg', 'bh', 'bi',
    'bj', 'bl', 'bm', 'bn', 'bo', 'bq', 'br', 'bs', 'bt', 'bw', 'by', 'bz',
    'ca', 'cd', 'cf', 'cg', 'ch', 'ci', 'ck', 'cl', 'cm', 'cn', 'co', 'cr',
    'cu', 'cv', 'cw', 'cy', 'cz', 'de', 'dj', 'dk', 'dm', 'do', 'dz', 'ec',
    'ee', 'eg', 'er', 'es', 'et', 'fi', 'fj', 'fk', 'fm', 'fo', 'fr', 'ga',
    'gb', 'gd', 'ge', 'gf', 'gg', 'gh', 'gi', 'gl', 'gm', 'gn', 'gp', 'gq',
    'gr', 'gt', 'gu', 'gw', 'gy', 'hk', 'hn', 'hr', 'ht', 'hu', 'id', 'ie',
    'il', 'im', 'in', 'io', 'iq', 'ir', 'is', 'it', 'je', 'jm', 'jo', 'jp',
    'ke', 'kg', 'kh', 'ki', 'km', 'kn', 'kp', 'kr', 'kw', 'ky', 'kz', 'la',
    'lb', 'lc', 'li', 'lk', 'lr', 'ls', 'lt', 'lu', 'lv', 'ly', 'ma', 'mc',
    'md', 'me', 'mf', 'mg', 'mh', 'mk', 'ml', 'mm', 'mn', 'mo', 'mp', 'mq',
    'mr', 'ms', 'mt', 'mu', 'mv', 'mw', 'mx', 'my', 'mz', 'na', 'nc', 'ne',
    'nf', 'ng', 'ni', 'nl', 'no', 'np', 'nr', 'nu', 'nz', 'om', 'pa', 'pe',
    'pf', 'pg', 'ph', 'pk', 'pl', 'pm', 'pr', 'ps', 'pt', 'pw', 'py', 'qa',
    're', 'ro', 'rs', 'ru', 'rw', 'sa', 'sb', 'sc', 'sd', 'se', 'sg', 'si',
    'sk', 'sl', 'sm', 'sn', 'so', 'sr', 'ss', 'st', 'sv', 'sx', 'sy', 'sz',
    'tc', 'td', 'tg', 'th', 'tj', 'tk', 'tl', 'tm', 'tn', 'to', 'tr', 'tt',
    'tv', 'tw', 'tz', 'ua', 'ug', 'us', 'uy', 'uz', 'va', 'vc', 've', 'vg',
    'vi', 'vn', 'vu', 'wf', 'ws', 'ye', 'yt', 'za', 'zm', 'zw',
  };

  /// Curated geosite domain lists per country code. Russia also gets the
  /// sites that only work from inside the country
  /// (`geosite-ru-available-only-inside`).
  static const geositeCountryTags = <String, List<String>>{
    'cn': ['geosite-cn'],
    'ru': ['geosite-category-ru', 'geosite-ru-available-only-inside'],
    'ir': ['geosite-category-ir'],
  };

  /// Lists of resources blocked in a country, used by
  /// `SingBoxRoutingRules.blockedInCountries`:
  ///
  /// * `ru` - domains and IP ranges blocked in Russia (runetfreedom, based on
  ///   the registry of blocked sites and community lists);
  /// * `cn` - sites outside mainland China (`geosite-geolocation-!cn`).
  static const blockedCountryTags = <String, List<String>>{
    'ru': ['geosite-ru-blocked', 'geoip-ru-blocked'],
    'cn': ['geosite-geolocation-!cn'],
  };

  static const _runetfreedom =
      'https://raw.githubusercontent.com/runetfreedom/russia-v2ray-rules-dat/release/sing-box';

  /// Download URLs of the rule-sets that are not published by SagerNet.
  static const thirdPartyUrls = <String, String>{
    'geosite-ru-blocked':
        '$_runetfreedom/rule-set-geosite/geosite-ru-blocked.srs',
    'geoip-ru-blocked': '$_runetfreedom/rule-set-geoip/geoip-ru-blocked.srs',
    'geosite-ru-available-only-inside':
        '$_runetfreedom/rule-set-geosite/geosite-ru-available-only-inside.srs',
  };

  static const _aliases = {'uk': 'gb', 'el': 'gr'};

  /// Normalizes a user entered country code (`RU`, ` ru `, `uk`) to the
  /// lower case ISO 3166-1 alpha-2 code used by the rule-sets, or returns
  /// `null` when no geoip rule-set exists for it.
  static String? normalizeCountryCode(String code) {
    var normalized = code.trim().toLowerCase();
    if (normalized.startsWith('geoip-')) normalized = normalized.substring(6);
    normalized = _aliases[normalized] ?? normalized;
    return geoipCountryCodes.contains(normalized) ? normalized : null;
  }

  /// Whether [code] can be used in `SingBoxRoutingRules.bypassCountries`.
  static bool isSupportedCountry(String code) =>
      normalizeCountryCode(code) != null;

  /// Tag of the geoip rule-set of [countryCode] (no validation).
  static String geoipTag(String countryCode) =>
      'geoip-${countryCode.trim().toLowerCase()}';

  /// Rule-set tags describing [countryCode]: the curated geosite lists (if
  /// any) followed by the geoip rule-set. Empty for unknown codes.
  static List<String> countryRuleSets(String countryCode) {
    final code = normalizeCountryCode(countryCode);
    if (code == null) return const [];
    return [...?geositeCountryTags[code], geoipTag(code)];
  }

  /// Whether [code] can be used in `SingBoxRoutingRules.blockedInCountries`.
  static bool isSupportedBlockedCountry(String code) =>
      blockedRuleSets(code).isNotEmpty;

  /// Rule-set tags of the resources blocked in [countryCode] (see
  /// [blockedCountryTags]). Empty for countries without such a list.
  static List<String> blockedRuleSets(String countryCode) {
    var code = countryCode.trim().toLowerCase();
    code = _aliases[code] ?? code;
    return [...?blockedCountryTags[code]];
  }

  /// Whether [tag] names a domain (geosite) rule-set, which may be used in
  /// DNS rules. IP rule-sets (`geoip-*`) must not be used in DNS rules.
  static bool isGeosite(String tag) => tag.startsWith('geosite-');

  /// Download URL of the rule-set [tag]: the fixed URL of a
  /// [thirdPartyUrls] entry, otherwise built from the SagerNet URL templates
  /// (`{tag}` placeholder).
  static String url(
    String tag, {
    String geoipUrl = SingBoxConfigOptions.defaultGeoipRuleSetUrl,
    String geositeUrl = SingBoxConfigOptions.defaultGeositeRuleSetUrl,
  }) {
    final fixed = thirdPartyUrls[tag];
    if (fixed != null) return fixed;
    final template = isGeosite(tag) ? geositeUrl : geoipUrl;
    return template.replaceAll('{tag}', tag);
  }

  /// A remote binary rule-set definition for `route.rule_set`.
  ///
  /// [httpClient] is the tag of an entry of the top-level `http_clients`
  /// used for downloading (sing-box 1.14).
  static Map<String, dynamic> remote(
    String tag, {
    String? httpClient,
    Duration updateInterval = const Duration(days: 1),
    String geoipUrl = SingBoxConfigOptions.defaultGeoipRuleSetUrl,
    String geositeUrl = SingBoxConfigOptions.defaultGeositeRuleSetUrl,
  }) {
    return {
      'type': 'remote',
      'tag': tag,
      'format': 'binary',
      'url': url(tag, geoipUrl: geoipUrl, geositeUrl: geositeUrl),
      if (httpClient != null) 'http_client': httpClient,
      'update_interval': formatDuration(updateInterval),
    };
  }
}
