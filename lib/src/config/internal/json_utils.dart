// Internal helpers for tolerant JSON handling. Not exported.

/// Returns [value] as a non-empty trimmed string, or `null`.
///
/// Numbers and booleans are converted with `toString()`.
String? readString(Object? value) {
  if (value == null) return null;
  if (value is String) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
  if (value is num || value is bool) return value.toString();
  return null;
}

/// Returns [value] as a bool. Accepts `true/false`, `1/0`, `"true"`,
/// `"1"`, `"yes"`, `"on"` and their negations.
bool? readBool(Object? value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    switch (value.trim().toLowerCase()) {
      case 'true' || '1' || 'yes' || 'on':
        return true;
      case 'false' || '0' || 'no' || 'off':
        return false;
    }
  }
  return null;
}

/// Returns [value] as an int; numeric strings are parsed.
int? readInt(Object? value) {
  if (value is int) return value;
  if (value is num && value.isFinite) return value.toInt();
  if (value is String) {
    final trimmed = value.trim();
    return int.tryParse(trimmed) ?? double.tryParse(trimmed)?.toInt();
  }
  return null;
}

/// Returns the strings in [value] (a list, or a single string), trimmed,
/// without empty entries.
List<String> readStringList(Object? value) {
  if (value is String) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? const [] : [trimmed];
  }
  if (value is! Iterable) return const [];
  return [
    for (final item in value)
      if (readString(item) case final String s) s,
  ];
}

/// Deep copies a JSON-like value, converting every map to
/// `Map<String, dynamic>` and every list to `List<dynamic>`.
Object? deepCopy(Object? value) {
  if (value is Map) {
    return <String, dynamic>{
      for (final entry in value.entries)
        entry.key.toString(): deepCopy(entry.value),
    };
  }
  if (value is List) return [for (final item in value) deepCopy(item)];
  return value;
}

/// Deep copies a JSON object.
Map<String, dynamic> deepCopyMap(Map<dynamic, dynamic> value) =>
    deepCopy(value)! as Map<String, dynamic>;

/// Returns [value] as a `Map<String, dynamic>` (copying when necessary), or
/// `null` when it is not a map.
Map<String, dynamic>? asJsonMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return deepCopyMap(value);
  return null;
}

/// Returns [base] if it is not in [taken], otherwise `base-2`, `base-3`, …
/// The returned tag is added to [taken].
String uniqueTag(String base, Set<String> taken, {String separator = '-'}) {
  var candidate = base;
  var n = 2;
  while (taken.contains(candidate)) {
    candidate = '$base$separator$n';
    n++;
  }
  taken.add(candidate);
  return candidate;
}

/// Removes duplicates from [values] while keeping the order.
List<String> dedupe(Iterable<String> values) {
  final seen = <String>{};
  return [
    for (final v in values)
      if (seen.add(v)) v,
  ];
}

/// Formats a [Duration] the way sing-box expects (`3m`, `90s`, `1h`, `1d`).
String formatDuration(Duration duration) {
  final seconds = duration.inSeconds;
  if (seconds <= 0) return '${duration.inMilliseconds}ms';
  if (seconds % 86400 == 0) return '${seconds ~/ 86400}d';
  if (seconds % 3600 == 0) return '${seconds ~/ 3600}h';
  if (seconds % 60 == 0) return '${seconds ~/ 60}m';
  return '${seconds}s';
}
