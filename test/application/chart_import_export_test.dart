import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:witrn_analyzer/application/analyzer_view_model.dart';
import 'package:witrn_analyzer/core/models.dart';
import 'package:witrn_analyzer/data/capture_repository.dart';
import 'package:witrn_analyzer/data/csv_capture_codec.dart';
import 'package:witrn_analyzer/data/csv_chart_codec.dart';

import '../fakes.dart';

void main() {
  late AnalyzerViewModel model;
  late MemoryCaptureRepository repository;
  late FakeFiles files;
  late FakeTransport transport;
  Uint8List bytes(String value) => Uint8List.fromList(utf8.encode(value));
  setUp(() {
    repository = MemoryCaptureRepository();
    files = FakeFiles();
    transport = FakeTransport();
    model = AnalyzerViewModel(
      transport: transport,
      repository: repository,
      files: files,
    );
  });
  tearDown(() async {
    await model.shutdown();
    model.dispose();
  });

  test(
    'chart and PD imports replace only their own data; exports remain separate',
    () async {
      await model.importBytes(
        bytes('Raw\nFE03E08100\nFE07E0A1112C910100'),
        'pd.csv',
      );
      final records = model.records.toList();
      final chart = [
        for (var i = 0; i < 80; i++)
          TelemetrySample(
            elapsedUs: i * 1000000,
            raw: [],
            voltage: 5 + i / 10,
            current: 2,
          ),
      ];
      await model.importChartBytes(
        const CsvChartCodec().encode(chart),
        'chart.csv',
      );
      expect(model.error, isNull);
      expect(model.records, records);
      expect(model.samples, hasLength(80));
      expect(model.latestTelemetry!.voltage, 12.9);
      expect(model.chartLinkedToMessages, isFalse);
      await model.exportChart();
      expect(files.saveTitle, '导出图表');
      expect(files.savedName, startsWith('WITRN_Chart_'));
      expect(const CsvChartCodec().decode(files.saved!), hasLength(80));
      await model.exportCsv();
      expect(files.saveTitle, '导出 PD 报文');
      expect(files.savedName, startsWith('WITRN_PD_'));
      expect(
        const CsvCaptureCodec().decode(files.saved!).records,
        hasLength(2),
      );
      await model.importBytes(
        bytes('Raw\nFE07E082122C210310'),
        'replacement.csv',
      );
      expect(model.records, hasLength(1));
      expect(model.samples, hasLength(80));
      expect(model.latestTelemetry!.voltage, 12.9);
      expect(model.chartFileName, 'chart.csv');
      await model.importChartBytes(bytes('Raw\nFE03E08100'), 'wrong.csv');
      expect(model.error, isNotNull);
      expect(model.samples, hasLength(80));
      expect(model.records, hasLength(1));
      expect(model.chartFileName, 'chart.csv');
      await model.importBytes(
        const CsvChartCodec().encode(chart),
        'wrong-pd.csv',
      );
      expect(model.error, isNotNull);
      expect(model.records, hasLength(1));
      expect(model.samples, hasLength(80));
    },
  );

  test(
    'only successful chart imports disconnect paused live capture',
    () async {
      await model.connect();
      transport.emit(parseHex('FE07E0A1112C910100'));
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(model.connected, isTrue);
      expect(model.recording, isTrue);
      model.pause();
      await model.importChartBytes(bytes('bad\nfile'), 'bad.csv');
      expect(model.connected, isTrue);
      await model.importChartBytes(
        bytes('elapsed_us,voltage_v\n0,5\n1000000,9'),
        'ok.csv',
      );
      expect(model.connected, isFalse);
      expect(model.samples.last.voltage, 9);
      expect(model.latestTelemetry!.voltage, 9);
      await model.connect();
      expect(model.chartFileName, isEmpty);
      expect(model.samples, isEmpty);
      expect(model.chartLinkedToMessages, isTrue);
    },
  );
}
