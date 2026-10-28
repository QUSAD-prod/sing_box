// Internal subscription parser. Not exported; see
// SingBoxShareLink.parseSubscription.

import 'dart:convert';

import '../outbound.dart';
import 'json_utils.dart';
import 'link_parser.dart';
import 'uri_parts.dart';

/// Parses subscription [content]; see `SingBoxShareLink.parseSubscription`.
List<SingBoxOutbound> parseSubscriptionContent(String content) {
  var text = _clean(content);
  if (text.isEmpty) return [];
  final fromJson = _tryJson(text);
  if (fromJson != null) return _uniqueTags(fromJson);
  if (!text.contains('://')) {
    final decoded = tryDecodeBase64(text);
    if (decoded != null) {
      text = _clean(decoded);
      final decodedJson = _tryJson(text);
      if (decodedJson != null) return _uniqueTags(decodedJson);
    }
  }
  final result = <SingBoxOutbound>[];
  for (final line in _lines(text)) {
    final outbound = _tryLink(line);
    if (outbound != null) {
      result.add(outbound);
      continue;
    }
    // Some providers base64 encode every line separately.
    if (!line.contains('://')) {
      final decoded = tryDecodeBase64(line);
      if (decoded != null && decoded.contains('://')) {
        for (final inner in _lines(_clean(decoded))) {
          final innerOutbound = _tryLink(inner);
          if (innerOutbound != null) result.add(innerOutbound);
        }
      }
    }
  }
  return _uniqueTags(result);
}

String _clean(String value) => value.replaceAll('﻿', '').trim();

Iterable<String> _lines(String text) sync* {
  for (final raw in text.split(RegExp(r'\r\n|\r|\n'))) {
    final line = raw.trim();
    if (line.isEmpty ||
        line.startsWith('#') ||
        line.startsWith('//') ||
        line.startsWith(';')) {
      continue;
    }
    yield line;
  }
}

SingBoxOutbound? _tryLink(String line) {
  try {
    return parseShareLink(line);
  } on FormatException {
    return null;
  } on ArgumentError {
    return null;
  }
}

List<SingBoxOutbound>? _tryJson(String text) {
  if (!text.startsWith('{') && !text.startsWith('[')) return null;
  final Object? decoded;
  try {
    decoded = jsonDecode(text);
  } on FormatException {
    return null;
  }
  final result = <SingBoxOutbound>[];
  void addObject(Object? item) {
    if (item is String) {
      final outbound = _tryLink(item);
      if (outbound != null) result.add(outbound);
      return;
    }
    if (item is! Map) return;
    final type = readString(item['type']);
    if (type == null || !SingBoxOutbound.isProxyType(type)) return;
    try {
      var json = deepCopyMap(item);
      if (type == 'wireguard') json = convertLegacyWireGuard(json);
      result.add(SingBoxOutbound.fromJson(json, name: readString(json['tag'])));
    } on ArgumentError {
      // Skip malformed entries.
    }
  }

  if (decoded is List) {
    decoded.forEach(addObject);
  } else if (decoded is Map) {
    if (decoded['outbounds'] is List || decoded['endpoints'] is List) {
      for (final item in (decoded['endpoints'] as List?) ?? const []) {
        addObject(item);
      }
      for (final item in (decoded['outbounds'] as List?) ?? const []) {
        addObject(item);
      }
    } else if (decoded['servers'] is List) {
      _sip008(decoded['servers'] as List, result);
    } else if (decoded['type'] != null) {
      addObject(decoded);
    } else {
      return null;
    }
  } else {
    return null;
  }
  return result;
}

/// SIP008 online configuration (`{"version": 1, "servers": [...]}`).
void _sip008(List<dynamic> servers, List<SingBoxOutbound> result) {
  for (final server in servers) {
    if (server is! Map) continue;
    final host = readString(server['server']);
    final port = readInt(server['server_port']);
    var method = readString(server['method'])?.toLowerCase();
    final password = server['password'];
    if (host == null || port == null || method == null || password is! String) {
      continue;
    }
    if (method == 'chacha20-poly1305') method = 'chacha20-ietf-poly1305';
    if (!shadowsocksMethods.contains(method)) continue;
    final name = readString(server['remarks']) ?? readString(server['id']);
    final plugin = readString(server['plugin']);
    final json = <String, dynamic>{
      'type': 'shadowsocks',
      'tag': name ?? 'shadowsocks-$host-$port',
      'server': host,
      'server_port': port,
      'method': method,
      'password': password,
      if (plugin == 'obfs-local' ||
          plugin == 'simple-obfs' ||
          plugin == 'v2ray-plugin') ...{
        'plugin': plugin == 'simple-obfs' ? 'obfs-local' : plugin,
        if (readString(server['plugin_opts']) case final opts?)
          'plugin_opts': opts,
      },
    };
    if (plugin != null && json['plugin'] == null) continue;
    result.add(SingBoxOutbound.fromJson(json, name: name));
  }
}

/// Makes tags unique: the second `name` becomes `name (2)`, and so on.
List<SingBoxOutbound> _uniqueTags(List<SingBoxOutbound> outbounds) {
  final taken = <String>{};
  final result = <SingBoxOutbound>[];
  for (final outbound in outbounds) {
    if (taken.add(outbound.tag)) {
      result.add(outbound);
      continue;
    }
    var n = 2;
    while (taken.contains('${outbound.tag} ($n)')) {
      n++;
    }
    final tag = '${outbound.tag} ($n)';
    taken.add(tag);
    result.add(outbound.withTag(tag));
  }
  return result;
}
