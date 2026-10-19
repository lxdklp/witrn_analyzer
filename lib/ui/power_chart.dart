import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:syncfusion_flutter_charts/charts.dart';

import '../application/analyzer_view_model.dart';
import '../core/models.dart';
import '../data/chart_snapshot.dart';
import 'telemetry_style.dart';

/// Keeps the chart's selected traces and viewport across layout and route changes.
class PowerChartController extends ChangeNotifier {
  final Set<TelemetryMetric> _visible = TelemetryMetric.values.toSet();
  double _zoomFactor = 1;
  double _zoomPosition = 0;
  bool _all = false;

  void _setVisible(TelemetryMetric metric, bool visible) {
    visible ? _visible.add(metric) : _visible.remove(metric);
    notifyListeners();
  }

  void _toggleWindow() {
    _all = !_all;
    _resetViewport();
  }

  void _resetViewport() {
    _zoomFactor = 1;
    _zoomPosition = 0;
    notifyListeners();
  }
}

class PowerChart extends StatefulWidget {
  const PowerChart({super.key, required this.model, this.controller})
    : _expanded = false;
  const PowerChart._expanded({required this.model, required this.controller})
    : _expanded = true;
  final AnalyzerViewModel model;
  final PowerChartController? controller;
  final bool _expanded;
  @override
  State<PowerChart> createState() => _PowerChartState();
}

class _PowerChartState extends State<PowerChart>
    with AutomaticKeepAliveClientMixin {
  late PowerChartController _controller;
  Set<TelemetryMetric> get _visible => _controller._visible;
  @override
  bool get wantKeepAlive => true;
  NumericAxisController? _timeAxis;
  final ZoomPanBehavior _zoomPan = ZoomPanBehavior(
    enablePinching: true,
    enablePanning: true,
    enableMouseWheelZooming: true,
    enableDoubleTapZooming: true,
    zoomMode: ZoomMode.x,
    maximumZoomLevel: .05,
  );
  Timer? _timer;
  ChartSnapshot? _snapshot;
  List<TelemetrySample> _chartSamples = const [];
  int _revision = -1;
  bool get _all => _controller._all;
  bool _openingExpanded = false;
  int? _selectedId;
  bool? _follow;
  List<CaptureRecord> _events = const [];
  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? PowerChartController();
    _controller.addListener(_viewChanged);
    _update();
    _timer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted && _revision != widget.model.repository.telemetryRevision) {
        setState(_update);
      }
    });
  }

  @override
  void didUpdateWidget(covariant PowerChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _controller.removeListener(_viewChanged);
      if (oldWidget.controller == null) _controller.dispose();
      _controller = widget.controller ?? PowerChartController();
      _controller.addListener(_viewChanged);
      _restoreViewport();
      _update();
    }
    // File switches and clear should update immediately, even in historical mode.
    if (widget.model.latestTelemetry == null ||
        (!widget.model.connected &&
            _revision != widget.model.repository.telemetryRevision) ||
        (!widget.model.followLatest &&
            _selectedId != widget.model.selected?.id) ||
        _follow != widget.model.followLatest ||
        _snapshot?.samples.isEmpty == true) {
      _update();
    }
  }

  void _viewChanged() {
    _restoreViewport();
    setState(_update);
  }

  void _restoreViewport() {
    final axis = _timeAxis;
    if (axis == null || !axis.axis.attached) return;
    axis.zoomFactor = _controller._zoomFactor;
    axis.zoomPosition = _controller._zoomPosition;
  }

  void _rememberViewport(ZoomPanArgs args) {
    if (args.axis?.name != 'time') return;
    _controller._zoomFactor = args.currentZoomFactor;
    _controller._zoomPosition = args.currentZoomPosition;
  }

  Future<void> _expand() async {
    if (_openingExpanded) return;
    _openingExpanded = true;
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) =>
              _ExpandedPowerChart(model: widget.model, controller: _controller),
        ),
      );
    } finally {
      if (mounted) {
        _openingExpanded = false;
        _restoreViewport();
        setState(_update);
      }
    }
  }

  Future<void> _fileAction(Future<void> Function() action) async {
    await action();
    if (!mounted || !widget._expanded || widget.model.error == null) return;
    // The main page's error banner is hidden behind the expanded chart.
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(widget.model.error!)));
  }

  void _update() {
    _revision = widget.model.repository.telemetryRevision;
    _selectedId = widget.model.selected?.id;
    _follow = widget.model.followLatest;
    _snapshot = ChartSnapshot.build(
      widget.model.samples,
      endSeconds:
          !widget.model.chartLinkedToMessages ||
              widget.model.followLatest ||
              widget.model.selected == null ||
              _all
          ? null
          : (widget.model.selected!.elapsedUs / 1e6 + 30),
      windowSeconds: _all ? null : 60,
    );
    _chartSamples = _samplesWithGaps(_snapshot!);
    _events =
        (widget.model.chartLinkedToMessages
                ? widget.model.records
                : <CaptureRecord>[])
            .where(
              (r) =>
                  r.message.isSourceCapabilities || r.message.request != null,
            )
            .where(
              (r) =>
                  r.elapsedUs / 1e6 >= _snapshot!.minX &&
                  r.elapsedUs / 1e6 <= _snapshot!.maxX,
            )
            .take(120)
            .toList();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.removeListener(_viewChanged);
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  List<TelemetrySample> _samplesWithGaps(ChartSnapshot snapshot) {
    final result = <TelemetrySample>[];
    TelemetrySample? previous;
    for (final sample in snapshot.samples) {
      if (previous != null &&
          snapshot.gaps.any(
            (us) => us > previous!.elapsedUs && us <= sample.elapsedUs,
          )) {
        // A null-valued sample breaks every series without dropping either
        // endpoint. Keep its timestamp ordered for zooming and hit testing.
        result.add(
          TelemetrySample(
            elapsedUs: (previous.elapsedUs + sample.elapsedUs) ~/ 2,
            raw: const [],
          ),
        );
      }
      result.add(sample);
      previous = sample;
    }
    return result;
  }

  void _selectRecord(TelemetrySample sample) {
    final model = widget.model;
    if (!model.chartLinkedToMessages) return;
    CaptureRecord? closest;
    for (final record in model.visibleRecords) {
      if (closest == null ||
          (record.elapsedUs - sample.elapsedUs).abs() <
              (closest.elapsedUs - sample.elapsedUs).abs()) {
        closest = record;
      }
    }
    if (closest != null) {
      model.select(closest);
      setState(_update);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final model = widget.model;
    final snapshot = _snapshot!;
    final active = TelemetryMetric.values.where(_visible.contains).toList();
    final scaled = active
        .where(
          (metric) => snapshot.samples.any(
            (sample) => metric.valueOf(sample)?.isFinite == true,
          ),
        )
        .toList();
    final leftMetrics = scaled
        .where(
          (metric) =>
              metric == TelemetryMetric.voltage ||
              metric == TelemetryMetric.current,
        )
        .toList();
    final rightMetrics = scaled
        .where(
          (metric) =>
              metric == TelemetryMetric.power ||
              metric == TelemetryMetric.temperature,
        )
        .toList();
    final colors = Theme.of(context).colorScheme;
    // Keep paired scales in compact gutters so four traces remain readable
    // on phones. Series and labels use the same normalized snapshot ranges.
    final axisLabelStyle = TextStyle(
      fontSize: MediaQuery.textScalerOf(context).scale(9),
      fontFamily: 'monospace',
      color: colors.onSurfaceVariant,
    );
    NumericAxis valueAxis(
      List<TelemetryMetric> metrics, {
      bool right = false,
    }) => NumericAxis(
      name: right ? 'right' : 'left',
      opposedPosition: right,
      isVisible: metrics.isNotEmpty,
      minimum: 0,
      maximum: 1,
      interval: .25,
      rangePadding: ChartRangePadding.none,
      axisLine: const AxisLine(width: 0),
      majorTickLines: const MajorTickLines(size: 0),
      majorGridLines: MajorGridLines(
        width: right && leftMetrics.isNotEmpty ? 0 : 1,
        color: colors.outlineVariant,
      ),
      labelStyle: axisLabelStyle,
      axisLabelFormatter: (details) => ChartAxisLabel(
        metrics
            .map(
              (metric) =>
                  '${snapshot.rangeFor(metric).valueAt(details.value.toDouble()).toStringAsFixed(1)} ${metric.unit}',
            )
            .join('\n'),
        axisLabelStyle,
      ),
    );
    const title = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.show_chart, size: 17),
        SizedBox(width: 8),
        Text('电源曲线', style: TextStyle(fontWeight: FontWeight.w600)),
      ],
    );
    final selectors = [
      for (final metric in TelemetryMetric.values)
        SizedBox(
          width: 120,
          child: CheckboxListTile(
            key: ValueKey(metric),
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            activeColor: metric.color,
            checkColor: Colors.white,
            title: Text(
              '${metric.label} · ${metric.unit}',
              style: const TextStyle(fontSize: 12),
            ),
            value: _visible.contains(metric),
            onChanged: (checked) =>
                _controller._setVisible(metric, checked == true),
          ),
        ),
    ];
    final actions = [
      IconButton(
        tooltip: '导入图表',
        icon: const Icon(Icons.file_open_outlined, size: 20),
        onPressed: model.canImport
            ? () => _fileAction(model.importChart)
            : null,
      ),
      IconButton(
        tooltip: '导出图表',
        icon: const Icon(Icons.save_alt, size: 20),
        onPressed: model.canExportChart
            ? () => _fileAction(model.exportChart)
            : null,
      ),
      TextButton(
        onPressed: _controller._toggleWindow,
        child: Text(_all ? '全部' : '60 秒'),
      ),
      IconButton(
        tooltip: '回到实时 / 最新',
        icon: Icon(
          Icons.my_location,
          color: model.followLatest ? colors.primary : null,
        ),
        onPressed: () {
          model.setFollow(true);
          _controller._resetViewport();
        },
      ),
      IconButton(
        tooltip: widget._expanded ? '退出放大' : '放大图表',
        icon: Icon(widget._expanded ? Icons.fullscreen_exit : Icons.fullscreen),
        onPressed: widget._expanded
            ? () => Navigator.of(context).pop()
            : _expand,
      ),
    ];
    Widget toolbar(List<Widget> children) => Wrap(
      spacing: 4,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: children,
    );
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
          child: LayoutBuilder(
            builder: (context, constraints) => constraints.maxWidth >= 600
                ? toolbar([title, ...selectors, ...actions])
                : Column(
                    children: [
                      toolbar([title, ...actions]),
                      toolbar(selectors),
                    ],
                  ),
          ),
        ),
        Expanded(
          child: active.isEmpty
              ? const Center(child: Text('请勾选要显示的曲线'))
              : snapshot.samples.isEmpty
              ? Center(
                  child: Text(
                    '连接设备或导入图表 CSV 后，电压、电流、功率与温度曲线将在此显示',
                    style: TextStyle(color: colors.onSurfaceVariant),
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
                  child: SfCartesianChart(
                    margin: EdgeInsets.zero,
                    plotAreaBorderWidth: 0,
                    primaryXAxis: NumericAxis(
                      name: 'time',
                      minimum: snapshot.minX,
                      maximum: snapshot.maxX,
                      interval: (snapshot.maxX - snapshot.minX) / 6,
                      rangePadding: ChartRangePadding.none,
                      initialZoomFactor: _controller._zoomFactor,
                      initialZoomPosition: _controller._zoomPosition,
                      onRendererCreated: (axis) => _timeAxis = axis,
                      axisLine: const AxisLine(width: 0),
                      majorTickLines: const MajorTickLines(size: 0),
                      majorGridLines: const MajorGridLines(width: 0),
                      edgeLabelPlacement: EdgeLabelPlacement.shift,
                      labelStyle: TextStyle(
                        fontSize: MediaQuery.textScalerOf(context).scale(10),
                        color: colors.onSurfaceVariant,
                      ),
                      axisLabelFormatter: (details) => ChartAxisLabel(
                        '${details.value.toStringAsFixed(0)} s',
                        details.textStyle,
                      ),
                      plotBands: [
                        for (final record in _events)
                          PlotBand(
                            start: record.elapsedUs / 1e6,
                            end: record.elapsedUs / 1e6,
                            borderColor: colors.outlineVariant,
                            borderWidth: 1,
                            dashArray: const [3, 5],
                          ),
                        if (model.chartLinkedToMessages &&
                            model.selected != null)
                          PlotBand(
                            start: model.selected!.elapsedUs / 1e6,
                            end: model.selected!.elapsedUs / 1e6,
                            borderColor: colors.primary,
                            borderWidth: 1.5,
                          ),
                      ],
                    ),
                    primaryYAxis: valueAxis(leftMetrics),
                    axes: [valueAxis(rightMetrics, right: true)],
                    series: [
                      for (final metric in active)
                        LineSeries<TelemetrySample, double>(
                          key: ValueKey(metric.name),
                          name: metric.label,
                          dataSource: _chartSamples,
                          xValueMapper: (sample, _) => sample.elapsedUs / 1e6,
                          yValueMapper: (sample, _) {
                            final value = metric.valueOf(sample);
                            return value == null || !value.isFinite
                                ? null
                                : snapshot.rangeFor(metric).normalize(value);
                          },
                          yAxisName:
                              metric == TelemetryMetric.voltage ||
                                  metric == TelemetryMetric.current
                              ? 'left'
                              : 'right',
                          color: metric.color,
                          width: 2.4,
                          animationDuration: 0,
                          emptyPointSettings: const EmptyPointSettings(
                            mode: EmptyPointMode.gap,
                          ),
                          onPointTap: (details) {
                            final index = details.pointIndex;
                            if (index != null && index < _chartSamples.length) {
                              _selectRecord(_chartSamples[index]);
                            }
                          },
                        ),
                    ],
                    tooltipBehavior: TooltipBehavior(
                      enable: true,
                      animationDuration: 0,
                      color: colors.surfaceContainerHighest,
                      builder: (data, point, series, pointIndex, seriesIndex) {
                        final sample = data as TelemetrySample;
                        return Padding(
                          padding: const EdgeInsets.all(8),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (final metric in active)
                                Text(
                                  '${metric.label} ${metric.valueOf(sample)?.isFinite == true ? metric.valueOf(sample)!.toStringAsFixed(3) : '—'} ${metric.unit}',
                                  style: TextStyle(
                                    color: metric.color,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                    zoomPanBehavior: _zoomPan,
                    onZooming: _rememberViewport,
                    onZoomEnd: _rememberViewport,
                    onZoomReset: _rememberViewport,
                  ),
                ),
        ),
      ],
    );
  }
}

class _ExpandedPowerChart extends StatefulWidget {
  const _ExpandedPowerChart({required this.model, required this.controller});

  final AnalyzerViewModel model;
  final PowerChartController controller;

  @override
  State<_ExpandedPowerChart> createState() => _ExpandedPowerChartState();
}

class _ExpandedPowerChartState extends State<_ExpandedPowerChart> {
  late final bool _rotate =
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  void initState() {
    super.initState();
    if (_rotate) {
      unawaited(
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]),
      );
    }
  }

  @override
  void dispose() {
    // The rest of the app follows the system's orientation preference.
    if (_rotate) unawaited(SystemChrome.setPreferredOrientations([]));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.escape): () =>
          Navigator.of(context).pop(),
    },
    child: Focus(
      autofocus: true,
      child: Scaffold(
        body: SafeArea(
          child: ListenableBuilder(
            listenable: widget.model,
            builder: (context, _) => Column(
              children: [
                _ExpandedTelemetry(sample: widget.model.latestTelemetry),
                Expanded(
                  child: PowerChart._expanded(
                    model: widget.model,
                    controller: widget.controller,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _ExpandedTelemetry extends StatelessWidget {
  const _ExpandedTelemetry({required this.sample});

  final TelemetrySample? sample;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: colors.surfaceContainerLow,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 560 ? 4 : 2;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 6,
                children: [
                  for (final metric in TelemetryMetric.values)
                    SizedBox(
                      width:
                          (constraints.maxWidth - 12 * (columns - 1)) / columns,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            metric == TelemetryMetric.voltage
                                ? '电压 · VBUS'
                                : metric.label,
                            style: TextStyle(
                              fontSize: 11,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              '${(sample == null ? null : metric.valueOf(sample!))?.toStringAsFixed(metric == TelemetryMetric.temperature ? 1 : 3) ?? '—'} ${metric.unit}',
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 20,
                                fontWeight: FontWeight.w600,
                                color: metric.color,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 24,
                runSpacing: 4,
                children: [
                  for (final item in [
                    ('CC1', sample?.cc1),
                    ('CC2', sample?.cc2),
                    ('D+', sample?.dp),
                    ('D−', sample?.dn),
                  ])
                    Text(
                      '${item.$1} ${item.$2?.toStringAsFixed(2) ?? '—'} V',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}
