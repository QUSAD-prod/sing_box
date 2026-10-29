import 'dart:convert';
import 'dart:io';

/// Kind of a [SingBoxCoreReport].
enum SingBoxCoreReportType {
  /// The core crashed (Go panic or fatal error): `go.log` holds the crash
  /// output.
  crash('crash_reports'),

  /// The core came close to (or hit) its memory limit; on iOS the system
  /// kills the Network Extension above about 50 MB. Holds the log, memory
  /// profiles and the connections at that time.
  outOfMemory('oom_reports');

  const SingBoxCoreReportType(this.directoryName);

  /// Directory below the core's working directory that holds these reports.
  final String directoryName;
}

/// A crash or out-of-memory report that the sing-box core wrote to its
/// working directory (see `SingBox.getCoreReports()`).
///
/// A report is a directory with `metadata.json` (core and app version,
/// platform, times), usually `configuration.json` (the configuration that
/// was running, with credentials) and the report data. Share [directory]
/// (for example zipped) with whoever investigates the problem.
///
/// ```dart
/// for (final report in await SingBox.instance.getCoreReports()) {
///   print('${report.type.name} ${report.createdAt}: ${report.files}');
/// }
/// ```
class SingBoxCoreReport {
  /// Creates a report.
  const SingBoxCoreReport({
    required this.type,
    required this.id,
    required this.directory,
    required this.createdAt,
    this.files = const [],
    this.metadata = const {},
  });

  /// What happened.
  final SingBoxCoreReportType type;

  /// Name of the report directory, e.g. `2026-10-29T15-04-05`.
  final String id;

  /// Absolute path of the report directory.
  final String directory;

  /// When the crash or the memory pressure happened (`crashedAt` /
  /// `recordedAt` of the metadata, else the directory's modification time).
  final DateTime createdAt;

  /// Names of the files in [directory], sorted.
  final List<String> files;

  /// Content of `metadata.json`: `source` (`Application`, `NetworkExtension`,
  /// `sing_box`), `appVersion`, `coreVersion`, `goVersion`, `platform`, …
  final Map<String, dynamic> metadata;

  /// Absolute path of the report file [name] (one of [files]).
  String path(String name) => '$directory/$name';

  /// Reads the text file [name] of the report, or `null` when it does not
  /// exist.
  Future<String?> readFile(String name) async {
    final file = File(path(name));
    if (!await file.exists()) return null;
    return utf8.decode(await file.readAsBytes(), allowMalformed: true);
  }

  @override
  String toString() =>
      'SingBoxCoreReport(${type.name}, $id, ${files.length} files)';
}

/// Reads the reports of every [SingBoxCoreReportType] below
/// [workingDirectory], newest first. Unreadable entries are skipped.
Future<List<SingBoxCoreReport>> loadCoreReports(String workingDirectory) async {
  final reports = <SingBoxCoreReport>[];
  for (final type in SingBoxCoreReportType.values) {
    final root = Directory('$workingDirectory/${type.directoryName}');
    if (!await root.exists()) continue;
    await for (final entry in root.list()) {
      if (entry is! Directory) continue;
      try {
        reports.add(await _readReport(type, entry));
      } on FileSystemException {
        continue;
      }
    }
  }
  reports.sort((a, b) => b.createdAt.compareTo(a.createdAt));
  return reports;
}

Future<SingBoxCoreReport> _readReport(
  SingBoxCoreReportType type,
  Directory directory,
) async {
  final files = <String>[
    await for (final entry in directory.list())
      if (entry is File) entry.uri.pathSegments.last,
  ]..sort();
  var metadata = const <String, dynamic>{};
  final metadataFile = File('${directory.path}/metadata.json');
  if (await metadataFile.exists()) {
    try {
      final decoded = jsonDecode(await metadataFile.readAsString());
      if (decoded is Map) metadata = Map<String, dynamic>.from(decoded);
    } on FormatException {
      // Keep the report without metadata.
    }
  }
  final time = metadata['crashedAt'] ?? metadata['recordedAt'];
  final createdAt =
      (time is String ? DateTime.tryParse(time) : null) ??
      (await directory.stat()).modified.toUtc();
  return SingBoxCoreReport(
    type: type,
    id: directory.uri.pathSegments.lastWhere((s) => s.isNotEmpty),
    directory: directory.path,
    createdAt: createdAt,
    files: files,
    metadata: metadata,
  );
}
