import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:witrn_analyzer/app.dart';
import 'package:witrn_analyzer/application/analyzer_view_model.dart';
import 'package:witrn_analyzer/data/capture_repository.dart';

import '../fakes.dart';

void main() {
  for (final size in [
    const Size(1360, 920),
    const Size(800, 600),
    const Size(390, 844),
    const Size(360, 640),
  ]) {
    testWidgets(
      'import, filtering and details fit ${size.width} × ${size.height}',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final model = AnalyzerViewModel(
          transport: FakeTransport(),
          repository: MemoryCaptureRepository(),
          files: FakeFiles(),
        );
        final rows = [
          'Raw',
          for (var i = 0; i < 20; i++) ...[
            'FE07E0A1112C910100',
            'FE03E08100',
            'FE07E082122C210310',
          ],
        ];
        await tester.runAsync(
          () => model.importBytes(
            Uint8List.fromList(utf8.encode(rows.join('\n'))),
            'capture.csv',
          ),
        );
        await tester.pumpWidget(WitrnAnalyzerApp(model: model));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(find.byTooltip('显示 GoodCRC'));
        await tester.pumpAndSettle();
        expect(model.visibleRecords, hasLength(60));
        await tester.tap(find.byTooltip('隐藏 GoodCRC'));
        await tester.pumpAndSettle();
        expect(model.visibleRecords, hasLength(40));
        if (size.width < 700) {
          await tester.tap(find.text('电参曲线'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.tap(find.text('报文').first);
          await tester.pumpAndSettle();
          // Latest records are followed; choose a visible Request row.
          await tester.tap(find.text('Request').last);
          await tester.pumpAndSettle();
          expect(find.text('报文详情'), findsOneWidget);
          expect(tester.takeException(), isNull);
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(model.shutdown);
        model.dispose();
        await tester.pump();
      },
    );
  }
}
