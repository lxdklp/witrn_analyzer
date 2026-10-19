import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:witrn_analyzer/app.dart';
import 'package:witrn_analyzer/application/analyzer_view_model.dart';
import 'package:witrn_analyzer/application/app_settings.dart';
import 'package:witrn_analyzer/core/models.dart';
import 'package:witrn_analyzer/data/capture_repository.dart';
import 'package:witrn_analyzer/ui/usb_connection_settings.dart';

import '../fakes.dart';

void main() {
  final vid = find.byKey(const ValueKey('usb-vid'));
  final pid = find.byKey(const ValueKey('usb-pid'));

  testWidgets('saved VID/PID configure both scanning and connecting', (
    tester,
  ) async {
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
    await settings.setUsbDeviceIds(vendorId: 0x1234, productId: 0x5678);
    await tester.pumpWidget(WitrnAnalyzerApp(model: model, settings: settings));
    await tester.pumpAndSettle();
    expect(transport.enumeratedIds, isNull);
    await model.refreshDevices();
    expect(transport.enumeratedIds, (0x1234, 0x5678));
    expect(model.selectedDevice, isNotNull);
    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextFormField>(vid).controller!.text, '1234');
    await tester.enterText(vid, '0xabcd');
    await tester.enterText(pid, '0001');
    await tester.tap(find.text('保存 VID / PID'));
    await tester.pumpAndSettle();
    expect(model.selectedDevice, isNull);
    expect(model.devices, isEmpty);
    expect(tester.widget<TextFormField>(vid).controller!.text, 'ABCD');
    await tester.runAsync(() async {
      await model.connect();
      transport.emit(parseHex('FE07E0A1112C910100'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
    expect(transport.enumeratedIds, (0xabcd, 1));
    expect(transport.openedIds, (0xabcd, 1));
    expect(model.connected, isTrue);
    expect(tester.widget<TextFormField>(vid).enabled, isFalse);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, '保存 VID / PID'),
          )
          .onPressed,
      isNull,
    );
    await tester.runAsync(model.disconnect);
    await tester.pumpAndSettle();
    await tester.tap(find.text('恢复默认'));
    await tester.pumpAndSettle();
    expect((settings.usbVendorId, settings.usbProductId), (0x0716, 0x5060));
    await model.refreshDevices();
    expect(transport.enumeratedIds, (0x0716, 0x5060));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(model.shutdown);
    model.dispose();
    settings.dispose();
  });

  testWidgets('USB form rejects malformed hex and fits a narrow screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final settings = AppSettings();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: UsbConnectionSettings(settings: settings, enabled: true),
          ),
        ),
      ),
    );
    expect(tester.widget<TextFormField>(vid).controller!.text, '0716');
    expect(tester.widget<TextFormField>(pid).controller!.text, '5060');
    for (final invalid in ['', 'xyz', '10000', '-1', '0x']) {
      await tester.enterText(vid, invalid);
      await tester.tap(find.text('保存 VID / PID'));
      await tester.pumpAndSettle();
      expect(find.text('请输入 1–4 位十六进制数，可带 0x 前缀'), findsOneWidget);
      expect(settings.usbVendorId, 0x0716);
      expect(tester.takeException(), isNull);
    }
    await tester.enterText(vid, '0Xffff');
    await tester.enterText(pid, '0');
    await tester.tap(find.text('保存 VID / PID'));
    await tester.pumpAndSettle();
    expect((settings.usbVendorId, settings.usbProductId), (0xffff, 0));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    settings.dispose();
  });
}
