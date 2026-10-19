import 'dart:convert';
import 'dart:typed_data';

import 'package:csv/csv.dart';

import '../core/models.dart';

/// Chart CSV is separate from the PD report CSV's Raw-based format.
final class CsvChartCodec {
  const CsvChartCodec();
  static const maxSamples = 60000;
  static const columns = [
    'elapsed_us',
    'voltage_v',
    'current_a',
    'power_w',
    'temperature_c',
    'cc1_v',
    'cc2_v',
    'dp_v',
    'dn_v',
  ];

  Uint8List encode(List<TelemetrySample> samples) {
    Object number(double? value) => value?.isFinite == true ? value! : '';
    return Uint8List.fromList(
      utf8.encode(
        Csv(addBom: true).encode([
          columns,
          for (final sample in samples)
            [
              sample.elapsedUs,
              number(sample.voltage),
              number(sample.current),
              number(sample.power),
              number(sample.temperature),
              number(sample.cc1),
              number(sample.cc2),
              number(sample.dp),
              number(sample.dn),
            ],
        ]),
      ),
    );
  }

  List<TelemetrySample> decode(Uint8List bytes) {
    if (bytes.length > 64 * 1024 * 1024) {
      throw const FormatException('图表 CSV 不能超过 64 MiB');
    }
    final rows = Csv(autoDetect: false)
        .decode(utf8.decode(bytes).replaceFirst(RegExp('^\ufeff'), ''));
    if (rows.isEmpty) throw const FormatException('图表 CSV 为空');
    final headers = rows.first
        .map((cell) => cell.toString().trim().toLowerCase())
        .toList();
    if (!headers.contains('elapsed_us') ||
        !columns.skip(1).take(4).any(headers.contains)) {
      throw const FormatException(
        '请选择图表 CSV：需要 elapsed_us 时间列和电参数据列；PD 报文请使用“导入报文”',
      );
    }
    if (headers.toSet().length != headers.length) {
      throw const FormatException('图表 CSV 存在重复列名');
    }
    final samples = <TelemetrySample>[];
    for (var i = 1; i < rows.length; i++) {
      final row = rows[i];
      if (row.every((cell) => cell.toString().trim().isEmpty)) continue;
      String cell(String column) {
        final index = headers.indexOf(column);
        return index >= 0 && index < row.length
            ? row[index].toString().trim()
            : '';
      }

      double? number(String column) {
        final text = cell(column);
        if (text.isEmpty) return null;
        final value = double.tryParse(text);
        if (value == null || !value.isFinite) {
          throw FormatException('图表第 ${i + 1} 行的 $column 不是有效数值');
        }
        return value;
      }

      final elapsedUs = int.tryParse(cell('elapsed_us'));
      if (elapsedUs == null ||
          elapsedUs < 0 ||
          elapsedUs > 9007199254740991 ||
          (samples.isNotEmpty && elapsedUs < samples.last.elapsedUs)) {
        throw FormatException('图表第 ${i + 1} 行的 elapsed_us 必须是递增的非负整数微秒');
      }
      if (samples.length >= maxSamples) {
        throw const FormatException('图表超过 60,000 条采样，请拆分后导入');
      }
      samples.add(
        TelemetrySample(
          elapsedUs: elapsedUs,
          raw: const [],
          voltage: number('voltage_v'),
          current: number('current_a'),
          measuredPower: number('power_w'),
          temperature: number('temperature_c'),
          cc1: number('cc1_v'),
          cc2: number('cc2_v'),
          dp: number('dp_v'),
          dn: number('dn_v'),
        ),
      );
    }
    if (samples.isEmpty) throw const FormatException('图表 CSV 中没有采样数据');
    return samples;
  }
}
