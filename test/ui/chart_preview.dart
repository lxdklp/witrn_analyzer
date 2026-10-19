import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:witrn_analyzer/application/analyzer_view_model.dart';
import 'package:witrn_analyzer/core/models.dart';
import 'package:witrn_analyzer/core/pd_decoder.dart';
import 'package:witrn_analyzer/data/capture_repository.dart';
import 'package:witrn_analyzer/ui/power_chart.dart';
import '../fakes.dart';

void main() {
  testWidgets('chart migration visual check', (tester) async {
    await tester.runAsync(() async {
      final font = FontLoader('Preview')..addFont(File('/System/Library/AssetsV2/com_apple_MobileAsset_Font7/3419f2a427639ad8c8e139149a287865a90fa17e.asset/AssetData/PingFang.ttc').readAsBytes().then((b) => ByteData.sublistView(b)));
      await font.load();
      final mono = FontLoader('monospace')..addFont(File('/System/Library/Fonts/Supplemental/Arial.ttf').readAsBytes().then((b) => ByteData.sublistView(b)));
      await mono.load();
    });
    final repository = MemoryCaptureRepository();
    for (var i = 0; i <= 120; i++) {
      if (i > 70 && i < 80) continue;
      repository.addSample(TelemetrySample(
        elapsedUs: i * 500000, raw: [],
        voltage: 9 + math.sin(i / 10) * .3,
        current: 2 + math.cos(i / 15) * .8,
        temperature: 26 + i / 50,
      ));
    }
    final bytes = parseHex('FE07E0A1112C910100');
    final record = CaptureRecord(id: 1, elapsedUs: 15000000, time: null,
      message: (PdDecoder().decode(bytes) as PdReport).message, report: bytes);
    repository.addRecord(record);
    final model = AnalyzerViewModel(transport: FakeTransport(), repository: repository, files: FakeFiles())
      ..latestTelemetry = repository.samples.last
      ..selected = record;
    const key = ValueKey('preview');
    for (final scenario in [('desktop', const Size(1000, 550), Brightness.light), ('phone', const Size(390, 600), Brightness.dark)]) {
      tester.view.physicalSize = scenario.$2;
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(fontFamily: 'Preview', colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal, brightness: scenario.$3)),
        home: RepaintBoundary(key: key, child: Scaffold(body: PowerChart(model: model))),
      ));
      await tester.pumpAndSettle();
      final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(key));
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('/tmp/witrn-syncfusion-${scenario.$1}.png').writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
    await tester.pumpWidget(const SizedBox.shrink());
    model.dispose();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}
