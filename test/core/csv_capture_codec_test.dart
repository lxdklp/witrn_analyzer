import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:witrn_analyzer/data/csv_capture_codec.dart';

void main() {
  const codec = CsvCaptureCodec();
  Uint8List bytes(String text) => Uint8List.fromList(utf8.encode(text));
  test('BOM, mixed-case columns, quoted comma and newline, hex spacing', () {
    final result = codec.decode(
      bytes(
        '\ufeff TiMe ,RaW,详细数据\r\n23:59:59.900,"0xFE 07 E0 A1 11 2C 91 01 00","a,b\nnext"\r\n00:00:00.100,FE07E082122C210310,request',
      ),
    );
    expect(result.records, hasLength(2));
    expect(result.records.last.elapsedUs, 200000);
    expect(result.records.last.message.request!.current, 2);
    final restored = codec.decode(codec.encode(result.records));
    expect(
      restored.records.map((r) => r.rawHex),
      result.records.map((r) => r.rawHex),
    );
    expect(
      restored.records.map((r) => r.clockTime),
      result.records.map((r) => r.clockTime),
    );
  });
  test(
    'fresh context per file, malformed rows diagnosed, no silent truncation',
    () {
      codec.decode(bytes('Raw\nFE07E0A1112C910100'));
      final result = codec.decode(
        bytes('Raw\nFE07E082122C210310\nFE3\nzz\n${'00' * 65}'),
      );
      expect(
        result.records.single.message.diagnostics.map((d) => d.code),
        contains('missingContext'),
      );
      expect(result.skippedRows, 3);
      expect(result.diagnostics, isNotEmpty);
    },
  );
  test('no valid rows or missing Raw fails, all GoodCRC survive export', () {
    expect(() => codec.decode(bytes('wrong\n123')), throwsFormatException);
    expect(() => codec.decode(bytes('Raw\nFE')), throwsFormatException);
    final records = codec
        .decode(bytes('Raw\nFE03E08100\nFE07E0A1112C910100'))
        .records;
    expect(codec.decode(codec.encode(records)).records.length, 2);
    expect(
      codec.decode(codec.encode(records)).records.first.message.isGoodCrc,
      isTrue,
    );
  });
  test('out-of-order time stays in original row order with diagnostic', () {
    final result = codec.decode(
      bytes('时间,Raw\n12:00:02.000,FE03E08100\n12:00:01.000,FE03E08100'),
    );
    expect(result.records.last.elapsedUs, 0);
    expect(result.records.last.sourceTime, '12:00:01.000');
    expect(result.diagnostics.map((d) => d.code), contains('timestamp'));
  });
}
