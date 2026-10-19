import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:witrn_analyzer/app.dart';
import 'package:witrn_analyzer/application/analyzer_view_model.dart';
import 'package:witrn_analyzer/data/capture_file_service.dart';
import 'package:witrn_analyzer/data/capture_repository.dart';
import 'package:witrn_analyzer/data/csv_chart_codec.dart';

import '../fakes.dart';

void main() {
  testWidgets(
    'card actions route to separate files, including expanded chart',
    (tester) async {
      final files = FakeFiles();
      final model = AnalyzerViewModel(
        transport: FakeTransport(),
        repository: MemoryCaptureRepository(),
        files: files,
      );
      CaptureFile file(String name, String text) =>
          CaptureFile(name, Uint8List.fromList(utf8.encode(text)));
      Future<void> finishAction(String tooltip) async {
        await tester.tap(find.byTooltip(tooltip));
        for (var i = 0; i < 300 && model.busy; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump(const Duration(milliseconds: 10));
        }
        expect(model.busy, isFalse);
        await tester.pumpAndSettle();
      }

      await tester.pumpWidget(WitrnAnalyzerApp(model: model));
      await tester.pumpAndSettle();
      files.picked = file('pd.csv', 'Raw\nFE07E0A1112C910100');
      await finishAction('导入报文');
      expect(files.pickTitle, '导入 PD 报文');
      expect(model.records, hasLength(1));
      await finishAction('导出报文');
      expect(files.saveTitle, '导出 PD 报文');

      await tester.tap(find.text('电参曲线'));
      await tester.pumpAndSettle();
      files.picked = file('chart.csv', 'elapsed_us,voltage_v\n0,5\n1000000,9');
      await finishAction('导入图表');
      expect(files.pickTitle, '导入图表');
      expect(model.samples, hasLength(2));
      expect(model.records, hasLength(1));
      await tester.tap(find.byTooltip('放大图表'));
      await tester.pumpAndSettle();
      await finishAction('导出图表');
      expect(files.saveTitle, '导出图表');
      expect(const CsvChartCodec().decode(files.saved!), hasLength(2));

      files.picked = file('invalid.csv', 'not a chart');
      await finishAction('导入图表');
      expect(model.samples, hasLength(2));
      expect(find.byType(SnackBar), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(model.shutdown);
      model.dispose();
      await tester.pump();
    },
  );
}
