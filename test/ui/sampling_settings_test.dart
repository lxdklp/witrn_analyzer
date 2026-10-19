import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:witrn_analyzer/app.dart';
import 'package:witrn_analyzer/application/analyzer_view_model.dart';
import 'package:witrn_analyzer/application/app_settings.dart';
import 'package:witrn_analyzer/core/models.dart';
import 'package:witrn_analyzer/data/capture_repository.dart';

import '../fakes.dart';

void main() {
  testWidgets(
    'saved sampling rate reaches HID and slider works while connected',
    (tester) async {
      tester.view.physicalSize = const Size(1360, 920);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final transport = FakeTransport();
      final model = AnalyzerViewModel(
        transport: transport,
        repository: MemoryCaptureRepository(),
        files: FakeFiles(),
      );
      final settings = AppSettings();
      await settings.setHidReadRateHz(5);
      await tester.pumpWidget(
        WitrnAnalyzerApp(model: model, settings: settings),
      );
      await tester.pumpAndSettle();
      expect(transport.readRateHz, 5);
      expect(transport.openCount, 0);
      await tester.runAsync(() async {
        await model.connect();
        transport.emit(parseHex('FE07E0A1112C910100'));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle();
      expect(model.connected, isTrue);
      await tester.tap(find.byTooltip('设置'));
      await tester.pumpAndSettle();
      final slider = find.byKey(const ValueKey('hid-read-rate'));
      await tester.ensureVisible(slider);
      await tester.pumpAndSettle();
      expect(tester.widget<Slider>(slider).onChanged, isNotNull);
      final rect = tester.getRect(slider);
      await tester.tapAt(Offset(rect.left + 24, rect.center.dy));
      await tester.pumpAndSettle();
      expect(settings.hidReadRateHz, 1);
      expect(transport.readRateHz, 1);
      expect(find.text('1 Hz · 每 1000 ms 读取一次'), findsOneWidget);
      await tester.tapAt(Offset(rect.right - 24, rect.center.dy));
      await tester.pumpAndSettle();
      expect(settings.hidReadRateHz, 10);
      expect(transport.readRateHz, 10);
      expect(transport.openCount, 1);
      expect(transport.closeCount, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(model.shutdown);
      model.dispose();
      settings.dispose();
    },
  );
}
