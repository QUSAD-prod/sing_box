import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Path of a sing-box 1.14 CLI binary taken from the `SING_BOX_BIN`
/// environment variable, or `null` when the variable is not set.
///
/// Build it from the sing-box sources with
/// `go build -tags with_gvisor,with_quic,with_wireguard,with_utls,with_clash_api ./cmd/sing-box`
/// and run `SING_BOX_BIN=/path/to/sing-box flutter test test/config`.
final String? singBoxBinary = () {
  final value = Platform.environment['SING_BOX_BIN']?.trim();
  return value == null || value.isEmpty ? null : value;
}();

/// Runs `sing-box check` on [config]. Returns `null` when sing-box accepts
/// the configuration and the CLI output otherwise.
///
/// Must only be called when [singBoxBinary] is set.
Future<String?> runSingBoxCheck(Map<String, dynamic> config) async {
  final dir = await Directory.systemTemp.createTemp('sing_box_check');
  try {
    final file = File('${dir.path}/config.json');
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(config),
    );
    final result = await Process.run(singBoxBinary!, [
      'check',
      '-c',
      file.path,
      '-D',
      dir.path,
    ]);
    if (result.exitCode == 0) return null;
    return '${result.stdout}${result.stderr}'.trim();
  } finally {
    await dir.delete(recursive: true);
  }
}

/// Expects sing-box to accept [config] when `SING_BOX_BIN` is set; does
/// nothing otherwise (the structural assertions of the tests still run).
Future<void> expectSingBoxAccepts(
  Map<String, dynamic> config, {
  String? reason,
}) async {
  if (singBoxBinary == null) return;
  final error = await runSingBoxCheck(config);
  expect(
    error,
    isNull,
    reason:
        '${reason ?? 'sing-box check'} failed:\n$error\n'
        '${const JsonEncoder.withIndent('  ').convert(config)}',
  );
}
