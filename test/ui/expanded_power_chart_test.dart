import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'package:witrn_analyzer/app.dart';
import 'package:witrn_analyzer/application/analyzer_view_model.dart';
import 'package:witrn_analyzer/core/models.dart';
import 'package:witrn_analyzer/data/capture_repository.dart';
import 'package:witrn_analyzer/data/chart_snapshot.dart';
import 'package:witrn_analyzer/ui/power_chart.dart';

import '../fakes.dart';

void main() {
  late AnalyzerViewModel model;
  late List<MethodCall> orientationCalls;

  setUp(() {
    final repository = MemoryCaptureRepository();
    final sample = TelemetrySample(
      elapsedUs: 0,
      raw: [],
      voltage: 5,
      current: 2,
      temperature: 25,
      cc1: 1.2,
      cc2: 2.3,
      dp: .6,
      dn: .7,
    );
    repository.addSample(sample);
    model = AnalyzerViewModel(
      transport: FakeTransport(),
      repository: repository,
      files: FakeFiles(),
    )..latestTelemetry = sample;
    orientationCalls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'SystemChrome.setPreferredOrientations') {
            orientationCalls.add(call);
          }
          return null;
        });
  });

  tearDown(() {
    model.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  void setSize(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  void expectViewport(
    WidgetTester tester,
    double factor, [
    double position = 0,
  ]) {
    final renderer = tester
        .renderObject<LineSeriesRenderer<TelemetrySample, double>>(
          find.byType(LineSeries<TelemetrySample, double>).first,
        );
    expect(renderer.xAxis!.controller.zoomFactor, closeTo(factor, .0001));
    expect(renderer.xAxis!.controller.zoomPosition, closeTo(position, .0001));
  }

  testWidgets(
    'expanded chart shows live telemetry and preserves view settings on exit',
    (tester) async {
      setSize(tester, const Size(640, 360));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(title: const Text('主页面')),
            body: PowerChart(model: model),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey(TelemetryMetric.temperature)));
      await tester.tap(find.text('60 秒'));
      await tester.pumpAndSettle();
      final chart = tester.widget<SfCartesianChart>(
        find.byType(SfCartesianChart),
      );
      chart.zoomPanBehavior!.zoomByFactor(.5);
      await tester.pumpAndSettle();
      expectViewport(tester, .5);

      await tester.tap(find.byTooltip('放大图表'));
      await tester.pumpAndSettle();
      expect(find.text('主页面'), findsNothing);
      expect(find.text('5.000 V'), findsOneWidget);
      expect(find.text('2.000 A'), findsOneWidget);
      expect(find.text('10.000 W'), findsOneWidget);
      expect(find.text('25.0 °C'), findsOneWidget);
      for (final text in [
        'CC1 1.20 V',
        'CC2 2.30 V',
        'D+ 0.60 V',
        'D− 0.70 V',
      ]) {
        expect(find.text(text), findsOneWidget);
      }
      expect(find.text('全部'), findsOneWidget);
      expect(
        tester.widget<SfCartesianChart>(find.byType(SfCartesianChart)).series,
        hasLength(3),
      );
      expectViewport(tester, .5);
      final mobile = defaultTargetPlatform != TargetPlatform.macOS;
      expect(
        orientationCalls.map((call) => call.arguments).toList(),
        mobile
            ? [
                [
                  'DeviceOrientation.landscapeLeft',
                  'DeviceOrientation.landscapeRight',
                ],
              ]
            : isEmpty,
      );

      final next = TelemetrySample(
        elapsedUs: 1000000,
        raw: [],
        voltage: 9,
        current: 3,
        temperature: 28,
      );
      model.repository.addSample(next);
      model.latestTelemetry = next;
      model.setFollow(true);
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('9.000 V'), findsOneWidget);
      expect(find.text('27.000 W'), findsOneWidget);
      expect(
        tester
            .widget<SfCartesianChart>(find.byType(SfCartesianChart))
            .series
            .first
            .dataSource,
        hasLength(2),
      );
      await tester.tap(find.byKey(const ValueKey(TelemetryMetric.current)));
      await tester.pumpAndSettle();
      tester
          .widget<SfCartesianChart>(find.byType(SfCartesianChart))
          .zoomPanBehavior!
          .zoomByFactor(.25);
      await tester.pumpAndSettle();
      final expanded = tester
          .renderObject<LineSeriesRenderer<TelemetrySample, double>>(
            find.byType(LineSeries<TelemetrySample, double>).first,
          );
      await tester.timedDragFrom(
        expanded.localToGlobal(expanded.size.center(Offset.zero)),
        const Offset(-40, 0),
        const Duration(milliseconds: 400),
      );
      await tester.pumpAndSettle();
      final position = expanded.xAxis!.controller.zoomPosition;
      expect(position, greaterThan(0));
      await tester.tap(find.byTooltip('退出放大'));
      await tester.pumpAndSettle();
      expect(find.text('主页面'), findsOneWidget);
      expect(find.text('全部'), findsOneWidget);
      expect(
        tester.widget<SfCartesianChart>(find.byType(SfCartesianChart)).series,
        hasLength(2),
      );
      expectViewport(tester, .25, position);
      if (mobile) expect(orientationCalls.last.arguments, isEmpty);
      expect(tester.takeException(), isNull);

      // System back and desktop Escape must also leave the focused page.
      await tester.tap(find.byTooltip('放大图表'));
      await tester.pumpAndSettle();
      if (mobile) {
        await tester.binding.handlePopRoute();
      } else {
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      }
      await tester.pumpAndSettle();
      expect(find.byTooltip('放大图表'), findsOneWidget);
      expect(orientationCalls.length, mobile ? 4 : 0);
      if (mobile) expect(orientationCalls.last.arguments, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
      TargetPlatform.macOS,
    }),
  );

  testWidgets(
    'focused chart survives the main page changing layout on rotation',
    (tester) async {
      setSize(tester, const Size(390, 844));
      await tester.pumpWidget(WitrnAnalyzerApp(model: model));
      await tester.pumpAndSettle();
      await tester.tap(find.text('电参曲线'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey(TelemetryMetric.current)));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('放大图表'));
      await tester.pumpAndSettle();
      expect(find.byType(TabBar), findsNothing);
      expect(find.byTooltip('设置'), findsNothing);
      tester.view.physicalSize = const Size(932, 430);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('CC1 1.20 V'), findsOneWidget);
      expect(
        tester.widget<SfCartesianChart>(find.byType(SfCartesianChart)).series,
        hasLength(3),
      );
      await tester.tap(find.byTooltip('退出放大'));
      await tester.pumpAndSettle();
      tester.view.physicalSize = const Size(390, 844);
      await tester.pumpAndSettle();
      expect(find.byTooltip('放大图表'), findsOneWidget);
      expect(
        tester.widget<SfCartesianChart>(find.byType(SfCartesianChart)).series,
        hasLength(3),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
