import 'dart:convert';
import 'dart:typed_data';

import 'package:csv/csv.dart';

import '../core/models.dart';
import '../core/pd_decoder.dart';

final class CsvImportResult {
  CsvImportResult(this.records, this.diagnostics, this.skippedRows);
  final List<CaptureRecord> records;
  final List<Diagnostic> diagnostics;
  final int skippedRows;
}

final class CsvCaptureCodec {
  const CsvCaptureCodec();
  static const columns = [
    '序号',
    '时间',
    'SOP',
    'Rev',
    'PPR',
    'PDR',
    'Msg Type',
    '详细数据',
    'Raw',
  ];
  static const maxFileBytes = 64 * 1024 * 1024;
  static const maxRecords = 100000;

  CsvImportResult decode(
    Uint8List bytes, {
    DecodeProfile profile = DecodeProfile.witrnCompat,
    bool verifyCrc = false,
  }) {
    if (bytes.length > maxFileBytes) {
      throw const FormatException('CSV 文件不能超过 64 MiB，请先拆分文件');
    }
    final text = utf8.decode(bytes).replaceFirst(RegExp('^\ufeff'), '');
    final rows = Csv(autoDetect: false).decode(text);
    if (rows.isEmpty) throw const FormatException('CSV 文件为空');
    final headers = rows.first
        .map((v) => v.toString().trim().toLowerCase())
        .toList();
    final rawIndex = headers.indexOf('raw');
    final timeIndex = headers.contains('时间')
        ? headers.indexOf('时间')
        : headers.indexOf('time');
    if (rawIndex < 0) throw const FormatException('CSV 缺少 Raw 列');
    final decoder = PdDecoder(profile: profile, verifyCrc: verifyCrc);
    final records = <CaptureRecord>[];
    final diagnostics = <Diagnostic>[];
    final timeline = _CsvTimeline();
    var skipped = 0;
    void warn(String code, String message) {
      if (diagnostics.length < 500) diagnostics.add(Diagnostic(code, message));
    }

    for (var rowIndex = 1; rowIndex < rows.length; rowIndex++) {
      final row = rows[rowIndex];
      try {
        if (row.length <= rawIndex) throw const FormatException('缺少 Raw 单元格');
        final report = parseHex(row[rawIndex].toString());
        if (report.length > 64) throw const FormatException('报告超过 64 字节');
        final sourceTime = timeIndex >= 0 && row.length > timeIndex
            ? row[timeIndex].toString().trim()
            : '';
        final timestamp = timeline.add(sourceTime);
        if (timestamp.$2 != null) {
          warn('timestamp', '第 ${rowIndex + 1} 行：${timestamp.$2}');
        }
        switch (decoder.decode(report, elapsedUs: timestamp.$1)) {
          case PdReport(:final message):
            if (records.length >= maxRecords) {
              throw const FormatException('CSV 超过 100,000 条报文，请拆分后导入');
            }
            records.add(
              CaptureRecord(
                id: records.length + 1,
                elapsedUs: timestamp.$1,
                time: null,
                sourceTime: sourceTime,
                message: message,
                report: report,
              ),
            );
          case GeneralReport():
            skipped++;
            warn('telemetryRow', '第 ${rowIndex + 1} 行不是 PD 数据，已跳过');
          case InvalidReport(:final diagnostic):
            skipped++;
            warn(diagnostic.code, '第 ${rowIndex + 1} 行：${diagnostic.message}');
        }
      } on FormatException catch (error) {
        if (records.length >= maxRecords) rethrow;
        skipped++;
        warn('invalidCsvRow', '第 ${rowIndex + 1} 行：${error.message}');
      }
    }
    if (records.isEmpty) {
      throw const FormatException('CSV 中没有可导入的 PD 报文，原会话已保留');
    }
    return CsvImportResult(records, diagnostics, skipped);
  }

  Uint8List encode(List<CaptureRecord> records) => Uint8List.fromList(
    utf8.encode(
      Csv(addBom: true).encode([
        columns,
        for (final record in records)
          [
            record.id,
            record.clockTime == '—' ? '' : record.clockTime,
            record.message.sop,
            record.message.header?.revision ?? '',
            record.message.powerRole,
            record.message.dataRole,
            record.message.type,
            _describe(record.message),
            record.rawHex,
          ],
      ]),
    ),
  );

  String _describe(PdMessage message) {
    final lines = <String>[message.summary];
    void visit(FieldNode node, String prefix) {
      lines.add('$prefix${node.label}: ${node.displayValue}');
      for (final child in node.children) {
        visit(child, '$prefix  ');
      }
    }

    for (final node in message.fields) {
      visit(node, '');
    }
    lines.addAll(message.diagnostics.map((d) => d.toString()));
    return lines.join('\n');
  }
}

final class _CsvTimeline {
  int? _origin;
  int? _lastWall;
  var _days = 0;
  var _elapsed = 0;
  (int, String?) add(String text) {
    final match = RegExp(r'^(\d{1,2}):(\d{2}):(\d{2})(?:\.(\d{1,6}))?$')
        .firstMatch(text);
    if (match == null) {
      return (_elapsed, text.isEmpty ? '时间缺省，沿用上一相对时间' : '无法解析时间，保留原值');
    }
    final h = int.parse(match[1]!);
    final m = int.parse(match[2]!);
    final s = int.parse(match[3]!);
    if (h > 23 || m > 59 || s > 59) return (_elapsed, '时间超出有效范围');
    final micros = int.parse((match[4] ?? '').padRight(6, '0'));
    final wall = ((h * 60 + m) * 60 + s) * 1000000 + micros;
    if (_lastWall != null && _lastWall! - wall > 12 * 3600 * 1000000) _days++;
    _lastWall = wall;
    final absolute = _days * 86400 * 1000000 + wall;
    _origin ??= absolute;
    final elapsed = absolute - _origin!;
    if (elapsed < _elapsed) return (_elapsed, '时间倒退，保持文件顺序并钳制相对时间');
    _elapsed = elapsed;
    return (_elapsed, null);
  }
}
