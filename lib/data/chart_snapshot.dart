import 'dart:math' as math;

import '../core/models.dart';

enum TelemetryMetric {
  voltage,
  current,
  power,
  temperature;

  double? valueOf(TelemetrySample sample) => switch (this) {
    voltage => sample.voltage,
    current => sample.current,
    power => sample.power,
    temperature => sample.temperature,
  };
}

final class AxisRange {
  const AxisRange(this.min, this.max);
  final double min, max;
  double normalize(double value) => (value - min) / (max - min);
  double valueAt(double y) => min + y * (max - min);
  factory AxisRange.fromValues(Iterable<double?> input) {
    final values = input.whereType<double>().where((v) => v.isFinite).toList();
    if (values.isEmpty) return const AxisRange(0, 1);
    var min = values.reduce(math.min);
    var max = values.reduce(math.max);
    final padding = math.max((max - min) * .12, math.max(max.abs(), 1) * .025);
    min -= padding;
    max += padding;
    return AxisRange(min, max);
  }
}

final class ChartSnapshot {
  ChartSnapshot({
    required this.samples,
    required this.gaps,
    required this.voltage,
    required this.current,
    required this.power,
    required this.temperature,
    required this.minX,
    required this.maxX,
  });
  final List<TelemetrySample> samples;
  final List<int> gaps;
  final AxisRange voltage, current, power, temperature;
  AxisRange rangeFor(TelemetryMetric metric) => switch (metric) {
    TelemetryMetric.voltage => voltage,
    TelemetryMetric.current => current,
    TelemetryMetric.power => power,
    TelemetryMetric.temperature => temperature,
  };
  final double minX, maxX;
  factory ChartSnapshot.build(
    List<TelemetrySample> input, {
    double? endSeconds,
    double? windowSeconds = 60,
    int maxPoints = 600,
  }) {
    final end = endSeconds ?? (input.lastOrNull?.elapsedUs ?? 0) / 1e6;
    final start = windowSeconds == null
        ? (input.firstOrNull?.elapsedUs ?? 0) / 1e6
        : math.max(0.0, end - windowSeconds);
    final visible = input
        .where((s) => s.elapsedUs / 1e6 >= start && s.elapsedUs / 1e6 <= end)
        .toList();
    final voltage = AxisRange.fromValues(visible.map((s) => s.voltage));
    final current = AxisRange.fromValues(visible.map((s) => s.current));
    final power = AxisRange.fromValues(visible.map((s) => s.power));
    final temperature = AxisRange.fromValues(visible.map((s) => s.temperature));
    final gaps = <int>[
      for (var i = 1; i < visible.length; i++)
        if (visible[i].elapsedUs - visible[i - 1].elapsedUs > 1000000)
          visible[i].elapsedUs,
    ];
    final picked = <int>{};
    if (visible.length <= maxPoints) {
      picked.addAll(List.generate(visible.length, (i) => i));
    } else {
      // Each bucket keeps both endpoints and min/max for all four metrics.
      final bucketCount = math.max(1, maxPoints ~/ 10);
      final bucket = (visible.length / bucketCount).ceil();
      for (var offset = 0; offset < visible.length; offset += bucket) {
        final end = math.min(offset + bucket, visible.length);
        picked.add(offset);
        picked.add(end - 1);
        for (final metric in TelemetryMetric.values) {
          final get = metric.valueOf;
          int? low, high;
          for (var i = offset; i < end; i++) {
            final value = get(visible[i]);
            if (value == null || !value.isFinite) {
              // Preserve missing-data boundaries without retaining every point
              // when a metric (for example temperature) is absent throughout.
              if ((i > 0 && get(visible[i - 1])?.isFinite == true) ||
                  (i + 1 < visible.length &&
                      get(visible[i + 1])?.isFinite == true)) {
                picked.add(i);
              }
              continue;
            }
            if (low == null || value < get(visible[low])!) low = i;
            if (high == null || value > get(visible[high])!) high = i;
          }
          if (low != null) picked.add(low);
          if (high != null) picked.add(high);
        }
      }
    }
    final indices = picked.toList()..sort();
    return ChartSnapshot(
      samples: [for (final index in indices) visible[index]],
      gaps: gaps,
      voltage: voltage,
      current: current,
      power: power,
      temperature: temperature,
      minX: start,
      maxX: math.max(start + 1, end),
    );
  }
  TelemetrySample? nearest(double seconds) {
    if (samples.isEmpty) return null;
    var low = 0;
    var high = samples.length - 1;
    while (low < high) {
      final middle = (low + high) ~/ 2;
      if (samples[middle].elapsedUs / 1e6 < seconds) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    if (low > 0 &&
        (samples[low - 1].elapsedUs / 1e6 - seconds).abs() <
            (samples[low].elapsedUs / 1e6 - seconds).abs()) {
      low--;
    }
    return samples[low];
  }
}
