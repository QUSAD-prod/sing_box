/// Validation helpers for user supplied network values.
abstract final class SingBoxValidators {
  static final _ipv4 = RegExp(
    r'^((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)\.){3}(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)$',
  );

  static final _domain = RegExp(
    r'^(?=.{1,253}$)(\*\.)?([a-zA-Z0-9_]([a-zA-Z0-9_-]{0,61}[a-zA-Z0-9_])?\.)*'
    r'[a-zA-Z0-9_]([a-zA-Z0-9_-]{0,61}[a-zA-Z0-9_])?\.?$',
  );

  static final _packageName = RegExp(
    r'^[a-zA-Z][a-zA-Z0-9_]*(\.[a-zA-Z0-9_]+)+$',
  );

  /// Whether [value] is a valid IPv4 address.
  static bool isIpv4(String value) => _ipv4.hasMatch(value);

  /// Whether [value] is a valid IPv6 address (optionally with a `%zone`).
  static bool isIpv6(String value) {
    var address = value;
    final zone = address.indexOf('%');
    if (zone >= 0) address = address.substring(0, zone);
    if (address.isEmpty || !address.contains(':')) return false;
    try {
      Uri.parseIPv6Address(address);
      return true;
    } on FormatException {
      return false;
    }
  }

  /// Whether [value] is a valid IPv4 or IPv6 address.
  static bool isIp(String value) => isIpv4(value) || isIpv6(value);

  /// Whether [value] is a CIDR subnet such as `192.168.0.0/16` or
  /// `fd00::/8`. A plain IP address is accepted as a host route.
  static bool isCidr(String value) {
    final slash = value.indexOf('/');
    if (slash < 0) return isIp(value);
    final address = value.substring(0, slash);
    final prefix = int.tryParse(value.substring(slash + 1));
    if (prefix == null || prefix < 0) return false;
    if (isIpv4(address)) return prefix <= 32;
    if (isIpv6(address)) return prefix <= 128;
    return false;
  }

  /// Normalizes a plain IP address to a CIDR host route (`/32` or `/128`);
  /// CIDRs are returned unchanged. Returns `null` for invalid input.
  static String? normalizeCidr(String value) {
    final trimmed = value.trim();
    if (!isCidr(trimmed)) return null;
    if (trimmed.contains('/')) return trimmed;
    return isIpv4(trimmed) ? '$trimmed/32' : '$trimmed/128';
  }

  /// Whether [value] looks like a domain name (`example.com`,
  /// `*.example.com`, `localhost`).
  static bool isDomain(String value) => _domain.hasMatch(value) && !isIp(value);

  /// Normalizes a user entered domain: trims, lowercases, strips a scheme,
  /// path, port and leading `*.`/`.`. Returns `null` if the result is not a
  /// valid domain.
  static String? normalizeDomain(String value) {
    var domain = value.trim().toLowerCase();
    final scheme = domain.indexOf('://');
    if (scheme >= 0) domain = domain.substring(scheme + 3);
    final slash = domain.indexOf('/');
    if (slash >= 0) domain = domain.substring(0, slash);
    final at = domain.lastIndexOf('@');
    if (at >= 0) domain = domain.substring(at + 1);
    final colon = domain.lastIndexOf(':');
    if (colon >= 0 && !domain.contains('[')) {
      domain = domain.substring(0, colon);
    }
    while (domain.startsWith('*.') || domain.startsWith('.')) {
      domain = domain.substring(domain.startsWith('*.') ? 2 : 1);
    }
    if (domain.endsWith('.')) domain = domain.substring(0, domain.length - 1);
    return domain.isNotEmpty && isDomain(domain) ? domain : null;
  }

  /// Whether [value] is a valid Android application id
  /// (e.g. `com.example.app`) or iOS bundle identifier.
  static bool isPackageName(String value) => _packageName.hasMatch(value);
}
