// Reading and minimal editing of Xcode `project.pbxproj` files for
// `dart run sing_box:setup_ios`. Pure Dart (no Flutter): the tool runs with
// `dart run`. Internal.

import 'dart:math';

/// A parsed `project.pbxproj` (old-style plist) that is edited by inserting
/// text, so Xcode's formatting and comments stay untouched.
class PbxProject {
  /// Parses [text].
  PbxProject(this.text) : _root = _Parser(text).parse() as Map<String, Object?>;

  /// The current file content.
  String text;
  Map<String, Object?> _root;

  final _random = Random.secure();

  /// All objects by id.
  Map<String, Map<String, Object?>> get objects => {
    for (final MapEntry(:key, :value)
        in (_root['objects']! as Map<String, Object?>).entries)
      key: value! as Map<String, Object?>,
  };

  /// Id of the PBXProject object.
  String get rootId => _root['rootObject']! as String;

  /// The PBXProject object.
  Map<String, Object?> get project => objects[rootId]!;

  /// Id of the native target [name], or `null`.
  String? targetId(String name) {
    final all = objects;
    for (final id in (project['targets']! as List).cast<String>()) {
      if (all[id]?['name'] == name) return id;
    }
    return null;
  }

  /// Build configurations (name → settings) of the list [listId].
  Map<String, Map<String, Object?>> configurations(String listId) {
    final all = objects;
    return {
      for (final id
          in (all[listId]!['buildConfigurations']! as List).cast<String>())
        all[id]!['name']! as String:
            (all[id]!['buildSettings'] as Map<String, Object?>?) ?? {},
    };
  }

  /// Ids of the configurations of [listId] by name.
  Map<String, String> configurationIds(String listId) {
    final all = objects;
    return {
      for (final id
          in (all[listId]!['buildConfigurations']! as List).cast<String>())
        all[id]!['name']! as String: id,
    };
  }

  /// Id of the local Swift package reference whose path ends with [name].
  String? localPackageId(String name) {
    final all = objects;
    for (final id
        in (project['packageReferences'] as List? ?? const []).cast<String>()) {
      final ref = all[id];
      if (ref?['isa'] == 'XCLocalSwiftPackageReference' &&
          (ref?['relativePath'] as String? ?? '').endsWith(name)) {
        return id;
      }
    }
    return null;
  }

  /// A new unique object id.
  String newId() {
    while (true) {
      final id =
          List.generate(
            24,
            (_) => '0123456789ABCDEF'[_random.nextInt(16)],
          ).join();
      if (!text.contains(id)) return id;
    }
  }

  /// Adds [objectText] (one or more `id = {...};` entries, indented with two
  /// tabs) to the section [isa], creating the section when needed.
  void addObjects(String isa, String objectText) {
    final end = '/* End $isa section */';
    final index = text.indexOf(end);
    if (index >= 0) {
      text = text.replaceRange(index, index, objectText);
    } else {
      final close = text.lastIndexOf('\t};\n\trootObject');
      if (close < 0) throw const FormatException('Unexpected project format');
      text = text.replaceRange(
        close,
        close,
        '\n/* Begin $isa section */\n$objectText$end\n',
      );
    }
    _reparse();
  }

  /// Inserts [line] (e.g. `ABC /* Name */,`) into the list [key] of the
  /// multi-line object [id], after the entry containing [after] or at the
  /// end.
  void addToList(String id, String key, String line, {String? after}) {
    final (start, end) = _objectRange(id);
    final body = text.substring(start, end);
    final open = body.indexOf('\t$key = (\n');
    if (open < 0) {
      // Missing list: add it before the object's closing brace.
      final close = body.lastIndexOf('\n');
      text = text.replaceRange(
        start + close,
        start + close,
        '\n\t\t\t$key = (\n\t\t\t\t$line\n\t\t\t);',
      );
      _reparse();
      return;
    }
    final listStart = open + '\t$key = (\n'.length;
    final listEnd = body.indexOf('\t\t\t);', listStart);
    var insertAt = listEnd;
    if (after != null) {
      final match = body.indexOf(after, listStart);
      if (match >= 0 && match < listEnd) {
        insertAt = body.indexOf('\n', match) + 1;
      }
    }
    text = text.replaceRange(
      start + insertAt,
      start + insertAt,
      '\t\t\t\t$line\n',
    );
    _reparse();
  }

  /// Sets [key] = [value] in the build settings of configuration [id].
  void setBuildSetting(String id, String key, String value) {
    final (start, end) = _objectRange(id);
    final body = text.substring(start, end);
    final existing = RegExp(
      '\\n\\t\\t\\t\\t${RegExp.escape(key)} = [^\\n]*;',
    ).firstMatch(body);
    final line = '\n\t\t\t\t$key = ${quote(value)};';
    if (existing != null) {
      text = text.replaceRange(
        start + existing.start,
        start + existing.end,
        line,
      );
    } else {
      final open = body.indexOf('buildSettings = {');
      final insertAt = open + 'buildSettings = {'.length;
      text = text.replaceRange(start + insertAt, start + insertAt, line);
    }
    _reparse();
  }

  (int, int) _objectRange(String id) {
    // The definition, not a reference to the object in another list.
    final match = RegExp(
      '\\n\\t\\t$id(?: /\\*[^\\n]*?\\*/)? = \\{',
    ).firstMatch(text);
    if (match == null) throw StateError('Object $id not found');
    final start = match.start + 1;
    final end = text.indexOf('\n\t\t};', start);
    if (end < 0) throw StateError('Object $id is not a multi-line object');
    return (start, end);
  }

  void _reparse() => _root = _Parser(text).parse() as Map<String, Object?>;

  /// [value] as a plist string, quoted when needed.
  static String quote(String value) =>
      RegExp(r'^[A-Za-z0-9_$./]+$').hasMatch(value)
          ? value
          : '"${value.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';
}

/// Parser of old-style (OpenStep) plists as used by `project.pbxproj`.
class _Parser {
  _Parser(this.text);

  final String text;
  var _i = 0;

  Object? parse() {
    _skip();
    return _value();
  }

  Object? _value() {
    _skip();
    final c = text[_i];
    if (c == '{') return _dict();
    if (c == '(') return _list();
    return _string();
  }

  Map<String, Object?> _dict() {
    _i++;
    final map = <String, Object?>{};
    while (true) {
      _skip();
      if (text[_i] == '}') {
        _i++;
        return map;
      }
      final key = _string();
      _skip();
      _expect('=');
      map[key] = _value();
      _skip();
      _expect(';');
    }
  }

  List<Object?> _list() {
    _i++;
    final list = <Object?>[];
    while (true) {
      _skip();
      if (text[_i] == ')') {
        _i++;
        return list;
      }
      list.add(_value());
      _skip();
      if (text[_i] == ',') _i++;
    }
  }

  String _string() {
    if (text[_i] == '"') {
      final buffer = StringBuffer();
      _i++;
      while (text[_i] != '"') {
        if (text[_i] == r'\') {
          _i++;
          final c = text[_i];
          buffer.write(switch (c) {
            'n' => '\n',
            't' => '\t',
            _ => c,
          });
        } else {
          buffer.write(text[_i]);
        }
        _i++;
      }
      _i++;
      return buffer.toString();
    }
    final start = _i;
    while (_i < text.length && RegExp(r'[^\s;,=(){}"]').hasMatch(text[_i])) {
      _i++;
    }
    if (start == _i) {
      throw FormatException('Unexpected character', text, _i);
    }
    return text.substring(start, _i);
  }

  void _expect(String c) {
    if (text[_i] != c) throw FormatException('Expected $c', text, _i);
    _i++;
  }

  void _skip() {
    while (_i < text.length) {
      final c = text[_i];
      if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
        _i++;
      } else if (text.startsWith('/*', _i)) {
        _i = text.indexOf('*/', _i) + 2;
      } else if (text.startsWith('//', _i)) {
        final end = text.indexOf('\n', _i);
        _i = end < 0 ? text.length : end;
      } else {
        return;
      }
    }
  }
}
