import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sing_box/src/models/core_report.dart';

void main() {
  late Directory working;

  setUp(() async {
    working = await Directory.systemTemp.createTemp('sing_box_reports');
  });

  tearDown(() => working.delete(recursive: true));

  Future<void> report(
    String kind,
    String id,
    Map<String, dynamic>? metadata, [
    Map<String, String> files = const {},
  ]) async {
    final directory = await Directory(
      '${working.path}/$kind/$id',
    ).create(recursive: true);
    if (metadata != null) {
      await File(
        '${directory.path}/metadata.json',
      ).writeAsString(jsonEncode(metadata));
    }
    for (final MapEntry(:key, :value) in files.entries) {
      await File('${directory.path}/$key').writeAsString(value);
    }
  }

  test('reads crash and OOM reports written by libbox, newest first', () async {
    await report(
      'crash_reports',
      '2026-10-29T10-00-00',
      {'source': 'NetworkExtension', 'crashedAt': '2026-10-29T10:00:00Z'},
      {'go.log': 'panic: boom', 'configuration.json': '{}'},
    );
    await report('oom_reports', '2026-10-29T12-00-00', {
      'recordedAt': '2026-10-29T12:00:00Z',
      'memoryUsage': '48 MB',
    });
    await report('crash_reports', 'broken', null, {'go.log': 'x'});
    // A stray file next to the report directories is ignored.
    await File('${working.path}/crash_reports/note.txt').writeAsString('x');

    final reports = await loadCoreReports(working.path);
    // The report without metadata dates from now (directory time).
    expect(reports.map((r) => r.id), [
      'broken',
      '2026-10-29T12-00-00',
      '2026-10-29T10-00-00',
    ]);
    final oom = reports[1];
    expect(oom.type, SingBoxCoreReportType.outOfMemory);
    expect(oom.id, '2026-10-29T12-00-00');
    expect(oom.createdAt, DateTime.utc(2026, 10, 29, 12));
    expect(oom.metadata['memoryUsage'], '48 MB');

    final crash = reports.firstWhere((r) => r.id == '2026-10-29T10-00-00');
    expect(crash.type, SingBoxCoreReportType.crash);
    expect(crash.files, ['configuration.json', 'go.log', 'metadata.json']);
    expect(await crash.readFile('go.log'), 'panic: boom');
    expect(await crash.readFile('missing'), isNull);
    expect(crash.path('go.log'), '${crash.directory}/go.log');

    // Without metadata the directory time is used.
    final broken = reports.firstWhere((r) => r.id == 'broken');
    expect(broken.metadata, isEmpty);
    expect(broken.files, ['go.log']);
  });

  test('no report directories means no reports', () async {
    expect(await loadCoreReports(working.path), isEmpty);
  });
}
