import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:witrn_analyzer/core/models.dart';
import 'package:witrn_analyzer/data/csv_chart_codec.dart';

void main() {
  const codec = CsvChartCodec();
  Uint8List bytes(String value) => Uint8List.fromList(utf8.encode(value));

  test(
    'chart CSV round-trips time, independent power and missing readings',
    () {
      final original = [
        TelemetrySample(
          elapsedUs: 123456,
          raw: [],
          voltage: 9.123456,
          current: -2,
          measuredPower: 17.5,
          temperature: 25.6,
          cc1: 1.2,
          cc2: 2.3,
          dp: .6,
          dn: .7,
        ),
        TelemetrySample(elapsedUs: 70000001, raw: [], voltage: 5, current: .3),
      ];
      final restored = codec.decode(codec.encode(original));
      expect(restored.map((s) => s.elapsedUs), [123456, 70000001]);
      expect(restored.first.voltage, 9.123456);
      expect(restored.first.current, -2);
      expect(restored.first.power, 17.5);
      expect(restored.first.temperature, 25.6);
      expect(
        [
          restored.first.cc1,
          restored.first.cc2,
          restored.first.dp,
          restored.first.dn,
        ],
        [1.2, 2.3, .6, .7],
      );
      expect(restored.last.power, 1.5);
      expect(restored.last.temperature, isNull);
      expect(restored.last.cc1, isNull);
    },
  );

  test('invalid chart files are rejected before replacing data', () {
    for (final text in [
      '',
      'Raw\nFE03E08100',
      'elapsed_us,voltage_v\n',
      'elapsed_us,voltage_v\n-1,5',
      'elapsed_us,voltage_v\n0,NaN',
      'elapsed_us,voltage_v\n0,Infinity',
      'elapsed_us,voltage_v\n0,bad',
      'elapsed_us,voltage_v\n10,5\n9,6',
      'elapsed_us,voltage_v,voltage_v\n0,5,6',
    ]) {
      expect(
        () => codec.decode(bytes(text)),
        throwsFormatException,
        reason: text,
      );
    }
    expect(
      () => codec.decode(
        bytes(
          'elapsed_us,voltage_v\n${List.generate(60001, (i) => '$i,5').join('\n')}',
        ),
      ),
      throwsFormatException,
    );
  });
}
