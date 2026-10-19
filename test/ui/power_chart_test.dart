import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'package:witrn_analyzer/app.dart';
import 'package:witrn_analyzer/application/analyzer_view_model.dart';
import 'package:witrn_analyzer/core/models.dart';
import 'package:witrn_analyzer/core/pd_decoder.dart';
import 'package:witrn_analyzer/data/capture_repository.dart';
import 'package:witrn_analyzer/data/chart_snapshot.dart';
import 'package:witrn_analyzer/ui/power_chart.dart';
import 'package:witrn_analyzer/ui/telemetry_style.dart';

import '../fakes.dart';

void main() {
  late AnalyzerViewModel model;
  setUp(() {
    final repository = MemoryCaptureRepository();
    for (var i = 0; i < 10; i++) {
      repository.addSample(
        TelemetrySample(
          elapsedUs: i * 100000,
          raw: [],
          voltage: 5,
          current: -2,
          temperature: i == 4 ? null : 25,
        ),
      );
    }
    model = AnalyzerViewModel(
      transport: FakeTransport(),
      repository: repository,
      files: FakeFiles(),
    );
    model.latestTelemetry = TelemetrySample(
      elapsedUs: 900000,
      raw: [],
      voltage: 5,
      current: -2,
      cc1: 1.2,
      cc2: 2.3,
      dp: .6,
      dn: .7,
      temperature: 25,
    );
  });
  tearDown(() => model.dispose());

  SfCartesianChart data(WidgetTester tester) =>
      tester.widget<SfCartesianChart>(find.byType(SfCartesianChart));

  LineSeriesRenderer<TelemetrySample, double> renderer(
    WidgetTester tester, {
    bool last = false,
  }) => tester.renderObject<LineSeriesRenderer<TelemetrySample, double>>(
    last
        ? find.byType(LineSeries<TelemetrySample, double>).last
        : find.byType(LineSeries<TelemetrySample, double>).first,
  );

  List<String> axisLabels(WidgetTester tester, {bool right = false}) =>
      renderer(tester, last: right).yAxis!.visibleLabels
          .singleWhere((label) => label.value == .5)
          .text
          .split('\n');

  testWidgets(
    'four independent selectors keep the correct series and tooltip units',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: PowerChart(model: model)),
        ),
      );
      expect(data(tester).series, hasLength(4));
      expect(
        data(tester).series.map((line) => line.dashArray),
        everyElement(isNull),
      );
      final temperature =
          data(tester).series.last as LineSeries<TelemetrySample, double>;
      expect(temperature.yValueMapper!(temperature.dataSource![4], 4), isNull);
      expect(axisLabels(tester), ['5.0 V', '-2.0 A']);
      expect(axisLabels(tester, right: true), ['10.0 W', '25.0 °C']);
      for (final metric in [TelemetryMetric.voltage, TelemetryMetric.current]) {
        await tester.tap(find.byKey(ValueKey(metric)));
        await tester.pumpAndSettle();
      }
      final chart = data(tester);
      expect(chart.series.map((line) => line.color), [
        TelemetryMetric.power.color,
        TelemetryMetric.temperature.color,
      ]);
      expect(chart.axes.single.isVisible, isTrue);
      expect(chart.primaryYAxis.isVisible, isFalse);
      chart.tooltipBehavior!.showByIndex(0, 0);
      await tester.pumpAndSettle();
      expect(find.text('功率 10.000 W'), findsOneWidget);
      expect(find.text('温度 25.000 °C'), findsOneWidget);
      expect(find.textContaining('0.500 W'), findsNothing);
      chart.tooltipBehavior!.hide();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey(TelemetryMetric.power)));
      await tester.pumpAndSettle();
      expect(
        data(tester).series.single.color,
        TelemetryMetric.temperature.color,
      );
      expect(data(tester).axes.single.isVisible, isTrue);
      expect(axisLabels(tester, right: true), ['25.0 °C']);
      await tester.tap(find.byKey(const ValueKey(TelemetryMetric.temperature)));
      await tester.pumpAndSettle();
      expect(find.text('请勾选要显示的曲线'), findsOneWidget);
      expect(find.byType(CheckboxListTile), findsNWidgets(4));
      await tester.tap(find.byKey(const ValueKey(TelemetryMetric.voltage)));
      await tester.pumpAndSettle();
      expect(data(tester).series.single.color, TelemetryMetric.voltage.color);
      expect(data(tester).primaryYAxis.isVisible, isTrue);
      expect(data(tester).axes.single.isVisible, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'gaps and non-finite values break traces without losing samples',
    (tester) async {
      model.repository.addSample(
        TelemetrySample(
          elapsedUs: 3000000,
          raw: [],
          voltage: 9,
          current: double.nan,
          temperature: double.infinity,
        ),
      );
      model.repository.addSample(
        TelemetrySample(
          elapsedUs: 3100000,
          raw: [],
          voltage: 9,
          current: 3,
          temperature: 26,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: PowerChart(model: model)),
        ),
      );
      await tester.pumpAndSettle();
      for (final line in data(
        tester,
      ).series.cast<LineSeries<TelemetrySample, double>>()) {
        final samples = line.dataSource!;
        expect(samples, hasLength(13));
        expect(samples[9].elapsedUs, 900000);
        expect(samples[10].elapsedUs, 1950000);
        expect(samples[11].elapsedUs, 3000000);
        expect(line.yValueMapper!(samples[10], 10), isNull);
        expect(line.yValueMapper!(samples[12], 12)!.isFinite, isTrue);
        if (line.name != TelemetryMetric.voltage.label) {
          expect(line.yValueMapper!(samples[11], 11), isNull);
        }
        expect(line.emptyPointSettings.mode, EmptyPointMode.gap);
      }
      expect(model.samples, hasLength(12));
      data(tester).tooltipBehavior!.showByIndex(0, 12);
      await tester.pumpAndSettle();
      expect(find.text('电压 9.000 V'), findsOneWidget);
      expect(find.text('电流 3.000 A'), findsOneWidget);
      expect(find.text('温度 26.000 °C'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'tapping a plotted sample selects its nearest message and event marker',
    (tester) async {
      final bytes = parseHex('FE07E0A1112C910100');
      final message = (PdDecoder().decode(bytes) as PdReport).message;
      final records = [
        for (final time in [100000, 720000])
          CaptureRecord(
            id: time,
            elapsedUs: time,
            time: null,
            message: message,
            report: bytes,
          ),
      ];
      for (final record in records) {
        model.repository.addRecord(record);
      }
      Future<void> render() => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: PowerChart(model: model)),
        ),
      );
      await render();
      await tester.pumpAndSettle();
      expect(data(tester).primaryXAxis.plotBands, hasLength(2));
      expect(data(tester).primaryXAxis.plotBands.first.dashArray, [3, 5]);
      final line = renderer(tester, last: true);
      final position = line.controller.pointToPixel(
        CartesianChartPoint<double>(x: .7, y: .5),
      );
      await tester.tapAt(line.localToGlobal(position));
      await tester.pumpAndSettle();
      expect(model.selected, same(records.last));
      expect(model.followLatest, isFalse);
      expect(data(tester).primaryXAxis.plotBands, hasLength(3));
      expect(data(tester).primaryXAxis.plotBands.last.start, .72);

      // Independently imported chart data has no common timeline with messages.
      model.chartFileName = 'independent.csv';
      model.selected = null;
      await render();
      await tester.pumpAndSettle();
      expect(data(tester).primaryXAxis.plotBands, isEmpty);
      final detached = renderer(tester, last: true);
      await tester.tapAt(
        detached.localToGlobal(
          detached.controller.pointToPixel(
            CartesianChartPoint<double>(x: .7, y: .5),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(model.selected, isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'horizontal zoom and pan reset with the window and live actions',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: PowerChart(model: model)),
        ),
      );
      await tester.pumpAndSettle();
      for (final action in [find.text('60 秒'), find.byTooltip('回到实时 / 最新')]) {
        data(tester).zoomPanBehavior!.zoomByFactor(.5);
        await tester.pumpAndSettle();
        final plot = renderer(tester);
        final center = plot.localToGlobal(plot.size.center(Offset.zero));
        await tester.timedDragFrom(
          center,
          const Offset(-60, 0),
          const Duration(milliseconds: 400),
        );
        await tester.pumpAndSettle();
        expect(plot.xAxis!.controller.zoomFactor, .5);
        expect(plot.xAxis!.controller.zoomPosition, greaterThan(0));
        expect(plot.yAxis!.controller.zoomFactor, 1);
        await tester.tap(action);
        await tester.pumpAndSettle();
        expect(plot.xAxis!.controller.zoomFactor, 1);
        expect(plot.xAxis!.controller.zoomPosition, 0);
      }
      expect(model.followLatest, isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('curve colors and visibility do not change with theme', (
    tester,
  ) async {
    Future<void> render(Color seed, Brightness brightness) => tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: seed,
            brightness: brightness,
          ),
        ),
        home: Scaffold(body: PowerChart(model: model)),
      ),
    );
    await render(Colors.green, Brightness.light);
    await tester.tap(find.byKey(const ValueKey(TelemetryMetric.current)));
    await tester.pumpAndSettle();
    final colors = data(tester).series.map((line) => line.color).toList();
    await render(Colors.purple, Brightness.dark);
    await tester.pumpAndSettle();
    expect(data(tester).series.map((line) => line.color), colors);
    expect(
      tester
          .widget<CheckboxListTile>(
            find.byKey(const ValueKey(TelemetryMetric.current)),
          )
          .value,
      isFalse,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('narrow chart reclaims gutters and fits scaled axis labels', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    Future<void> render(double scale) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: Scaffold(body: PowerChart(model: model)),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    double plotWidth() => renderer(tester).size.width;
    void expectLabelsInsideChart() {
      final bounds = tester.getRect(find.byType(SfCartesianChart));
      final plot = renderer(tester);
      final plotLeft = plot.localToGlobal(Offset.zero).dx;
      final plotRight = plotLeft + plot.size.width;
      for (final line
          in tester
              .renderObjectList<LineSeriesRenderer<TelemetrySample, double>>(
                find.byType(LineSeries<TelemetrySample, double>),
              )) {
        final axis = line.yAxis!;
        for (final label in axis.visibleLabels) {
          final available = axis.opposedPosition
              ? bounds.right - plotRight
              : plotLeft - bounds.left;
          expect(label.labelSize.width, lessThanOrEqualTo(available));
          expect(label.text, isNot(contains('...')));
        }
      }
      expect(tester.takeException(), isNull);
    }

    await render(1);
    final originalWidth = plotWidth();
    expect(originalWidth, greaterThan(250));
    expectLabelsInsideChart();

    await render(1.8);
    final scaledWidth = plotWidth();
    expect(scaledWidth, lessThan(originalWidth));
    expectLabelsInsideChart();

    for (final metric in [TelemetryMetric.power, TelemetryMetric.temperature]) {
      await tester.tap(find.byKey(ValueKey(metric)));
      await tester.pumpAndSettle();
    }
    expect(data(tester).axes.single.isVisible, isFalse);
    expect(plotWidth(), greaterThan(scaledWidth));
    expectLabelsInsideChart();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final size in [
    const Size(360, 640),
    const Size(800, 600),
    const Size(1360, 920),
  ]) {
    testWidgets('chart and selectors remain accessible at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(WitrnAnalyzerApp(model: model));
      await tester.pumpAndSettle();
      expect(find.byTooltip('显示 / 隐藏电参曲线'), findsNothing);
      if (size.width < 700) {
        expect(find.text('VBUS'), findsOneWidget);
        expect(find.text('5.000 V'), findsOneWidget);
        expect(find.text('CC1 1.2 V'), findsOneWidget);
        expect(
          tester.getTopLeft(find.text('VBUS')).dy,
          lessThan(tester.getTopLeft(find.byType(TabBar)).dy),
        );
      }
      final tabbed = size.width < 700 || size.height < 720;
      if (tabbed) {
        await tester.tap(find.text('电参曲线'));
        await tester.pumpAndSettle();
      }
      final temperature = find.byKey(
        const ValueKey(TelemetryMetric.temperature),
      );
      if (size.width >= 700) await tester.ensureVisible(temperature);
      await tester.pumpAndSettle();
      await tester.tap(temperature);
      await tester.pumpAndSettle();
      expect(data(tester).series, hasLength(3));
      if (tabbed) {
        await tester.tap(find.text('报文').first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('电参曲线'));
        await tester.pumpAndSettle();
        expect(tester.widget<CheckboxListTile>(temperature).value, isFalse);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  test('fixed trace colors have at least 3:1 contrast on light and dark theme surfaces', () {
    for (final seed in [
      Colors.green,
      Colors.teal,
      Colors.blue,
      Colors.indigo,
      Colors.purple,
      Colors.pink,
      Colors.red,
      Colors.orange,
      Colors.amber,
      Colors.brown,
      Colors.grey,
    ]) {
      for (final brightness in Brightness.values) {
        final scheme = ColorScheme.fromSeed(
          seedColor: seed,
          brightness: brightness,
        );
        for (final metric in TelemetryMetric.values) {
          final line = metric.color.computeLuminance();
          final surface = scheme.surface.computeLuminance();
          final contrast = line > surface
              ? (line + .05) / (surface + .05)
              : (surface + .05) / (line + .05);
          expect(
            contrast,
            greaterThanOrEqualTo(3),
            reason: '${metric.name}, $seed, $brightness',
          );
        }
      }
    }
  });
}
