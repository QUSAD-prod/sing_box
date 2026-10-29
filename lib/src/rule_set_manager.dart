// Downloads the rule-sets of the routing rules into the working directory so
// the configuration can read them as local files. Internal; used by
// SingBox.buildConfig / updateRuleSets.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'config/rule_sets.dart';
import 'models/rule_set_status.dart';

/// Keeps downloaded rule-sets in [directory] with an `index.json` of their
/// [SingBoxRuleSetStatus].
///
/// sing-box aborts the start when a remote rule-set cannot be downloaded the
/// first time; local files avoid that, and sing-box reloads a local file by
/// itself when it changes on disk.
class RuleSetManager {
  /// Creates a manager storing files in [directory].
  RuleSetManager(
    this.directory, {
    this.timeout = const Duration(seconds: 15),
    this.retryAfter = const Duration(minutes: 10),
    this.onWarning,
  });

  /// Where the rule-sets and `index.json` are stored.
  final Directory directory;

  /// Timeout of one download attempt (one URL).
  final Duration timeout;

  /// How long [prepare] waits before retrying a failed download (so that
  /// every connect does not wait for an unreachable host).
  final Duration retryAfter;

  /// Receives download problems.
  final void Function(String message, Map<String, dynamic> data)? onWarning;

  /// Largest accepted file.
  static const maxBytes = 32 * 1024 * 1024;

  final _changes = StreamController<List<SingBoxRuleSetStatus>>.broadcast();
  final _inflight = <String, Future<SingBoxRuleSetStatus>>{};
  Map<String, SingBoxRuleSetStatus>? _index;
  Future<void> _saving = Future<void>.value();

  /// Emits all statuses after every download attempt.
  Stream<List<SingBoxRuleSetStatus>> get changes => _changes.stream;

  /// The statuses of every rule-set downloaded or attempted so far.
  Future<List<SingBoxRuleSetStatus>> statuses() async =>
      (await _load()).values.toList();

  /// Makes the rule-sets [urls] (tag → URL) available and returns tag → path
  /// of the available files.
  ///
  /// Missing files and files of a changed URL are downloaded now (failed ones
  /// at most once per [retryAfter]); files older than [maxAge] are returned
  /// as they are and refreshed in the background.
  Future<Map<String, String>> prepare(
    Map<String, String> urls, {
    required Duration maxAge,
  }) async {
    final index = await _load();
    final now = DateTime.now();
    final waiting = <Future<SingBoxRuleSetStatus>>[];
    for (final MapEntry(key: tag, value: url) in urls.entries) {
      final status = index[tag];
      if (status != null && _usable(status, url)) {
        if (_isStale(status, maxAge, now)) unawaited(_download(tag, url));
        continue;
      }
      final attempt = status?.lastAttempt;
      if (status?.url == url &&
          attempt != null &&
          now.difference(attempt) < retryAfter) {
        continue;
      }
      waiting.add(_download(tag, url));
    }
    await Future.wait(waiting);
    return {
      for (final tag in urls.keys)
        if (index[tag] case final status? when _usable(status, urls[tag]!))
          tag: status.path!,
    };
  }

  /// Downloads the rule-sets [urls] now: all of them with [force], else the
  /// missing, failed and stale (older than [maxAge]) ones. Returns their
  /// statuses in the order of [urls].
  Future<List<SingBoxRuleSetStatus>> update(
    Map<String, String> urls, {
    required Duration maxAge,
    bool force = false,
  }) async {
    final index = await _load();
    final now = DateTime.now();
    await Future.wait([
      for (final MapEntry(key: tag, value: url) in urls.entries)
        if (force ||
            index[tag] == null ||
            !_usable(index[tag]!, url) ||
            _isStale(index[tag]!, maxAge, now))
          _download(tag, url),
    ]);
    return [
      for (final MapEntry(key: tag, value: url) in urls.entries)
        index[tag] ?? SingBoxRuleSetStatus(tag: tag, url: url),
    ];
  }

  /// Whether [status] has a file on disk downloaded from [url].
  bool _usable(SingBoxRuleSetStatus status, String url) =>
      status.url == url &&
      status.path != null &&
      File(status.path!).existsSync();

  static bool _isStale(
    SingBoxRuleSetStatus status,
    Duration maxAge,
    DateTime now,
  ) {
    final updated = status.updatedAt;
    return updated == null || now.difference(updated) > maxAge;
  }

  /// Downloads [tag] from [url] or its mirrors; one download per tag at a
  /// time.
  Future<SingBoxRuleSetStatus> _download(String tag, String url) {
    final running = _inflight[tag];
    if (running != null) return running;
    // A block body: returning the removed future from the callback would
    // make the future wait for itself.
    return _inflight[tag] = _downloadNow(tag, url).whenComplete(() {
      _inflight.remove(tag);
    });
  }

  Future<SingBoxRuleSetStatus> _downloadNow(String tag, String url) async {
    final index = await _load();
    final previous = index[tag];
    final json =
        Uri.tryParse(url)?.path.toLowerCase().endsWith('.json') ?? false;
    final file = File(
      '${directory.path}/${_fileName(tag)}${json ? '.json' : '.srs'}',
    );
    final errors = <String>[];
    SingBoxRuleSetStatus status;
    for (final candidate in [url, ...SingBoxRuleSets.mirrors(url)]) {
      try {
        final bytes = await _fetch(candidate);
        final invalid = _validate(bytes, json: json);
        if (invalid != null) throw FormatException(invalid);
        await directory.create(recursive: true);
        // Replace atomically: sing-box watches the file.
        final temp = File('${file.path}.tmp');
        await temp.writeAsBytes(bytes, flush: true);
        await temp.rename(file.path);
        final now = DateTime.now();
        status = SingBoxRuleSetStatus(
          tag: tag,
          url: url,
          path: file.path,
          updatedAt: now,
          size: bytes.length,
          lastAttempt: now,
        );
        index[tag] = status;
        await _save();
        return status;
      } on Object catch (e) {
        errors.add('$candidate: ${_describe(e)}');
      }
    }
    final error = errors.join('; ');
    onWarning?.call('Rule-set download failed', {'tag': tag, 'error': error});
    // A file from the same URL stays usable after a failed refresh.
    final keep = previous != null && previous.url == url;
    status = SingBoxRuleSetStatus(
      tag: tag,
      url: url,
      path: keep ? previous.path : null,
      updatedAt: keep ? previous.updatedAt : null,
      size: keep ? previous.size : null,
      lastError: error,
      lastAttempt: DateTime.now(),
    );
    index[tag] = status;
    await _save();
    return status;
  }

  Future<Uint8List> _fetch(String url) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      return await () async {
        final request = await client.getUrl(Uri.parse(url));
        final response = await request.close();
        if (response.statusCode < 200 || response.statusCode >= 300) {
          await response.drain<void>();
          throw HttpException(
            'HTTP ${response.statusCode} ${response.reasonPhrase}'.trim(),
          );
        }
        final bytes = BytesBuilder(copy: false);
        await for (final chunk in response) {
          bytes.add(chunk);
          if (bytes.length > maxBytes) {
            throw const HttpException('the file is too large');
          }
        }
        return bytes.takeBytes();
      }().timeout(timeout);
    } finally {
      client.close(force: true);
    }
  }

  /// Why [bytes] is not a rule-set, or `null` when it looks like one.
  static String? _validate(List<int> bytes, {required bool json}) {
    if (json) {
      try {
        final decoded = jsonDecode(utf8.decode(bytes));
        if (decoded is Map && decoded['rules'] is List) return null;
      } on FormatException {
        // Reported below.
      }
      return 'not a sing-box source rule-set';
    }
    // Binary rule-sets start with the magic bytes "SRS".
    if (bytes.length > 3 &&
        bytes[0] == 0x53 &&
        bytes[1] == 0x52 &&
        bytes[2] == 0x53) {
      return null;
    }
    return 'not a binary sing-box rule-set';
  }

  static String _describe(Object error) => switch (error) {
    TimeoutException() => 'timed out',
    HttpException(:final message) => message,
    FormatException(:final message) => message,
    SocketException(:final message, :final osError) =>
      osError == null ? message : '$message (${osError.message})',
    _ => '$error',
  };

  static String _fileName(String tag) =>
      tag.replaceAll(RegExp(r'[^A-Za-z0-9._!@-]'), '_');

  File get _indexFile => File('${directory.path}/index.json');

  Future<Map<String, SingBoxRuleSetStatus>> _load() async {
    final cached = _index;
    if (cached != null) return cached;
    final index = <String, SingBoxRuleSetStatus>{};
    try {
      final decoded = jsonDecode(await _indexFile.readAsString());
      if (decoded is List) {
        for (final item in decoded.whereType<Map<dynamic, dynamic>>()) {
          final status = SingBoxRuleSetStatus.tryFromMap(item);
          if (status != null) index[status.tag] = status;
        }
      }
    } on Object {
      // No index yet, or a broken one: start over.
    }
    return _index ??= index;
  }

  Future<void> _save() {
    final index = _index;
    if (index == null) return Future<void>.value();
    _changes.add(index.values.toList());
    return _saving = _saving.then((_) async {
      try {
        await directory.create(recursive: true);
        final temp = File('${_indexFile.path}.tmp');
        await temp.writeAsString(
          jsonEncode([for (final status in index.values) status.toMap()]),
        );
        await temp.rename(_indexFile.path);
      } on FileSystemException catch (e) {
        onWarning?.call('Could not save the rule-set index', {
          'error': e.toString(),
        });
      }
    });
  }

  /// Releases the change stream.
  Future<void> dispose() => _changes.close();
}
