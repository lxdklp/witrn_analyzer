import 'package:flutter/material.dart';

import '../data/chart_snapshot.dart';

/// Fixed mid-luminance colors remain visible on both light and dark surfaces.
extension TelemetryStyle on TelemetryMetric {
  String get label => switch (this) {
    TelemetryMetric.voltage => '电压',
    TelemetryMetric.current => '电流',
    TelemetryMetric.power => '功率',
    TelemetryMetric.temperature => '温度',
  };

  String get unit => switch (this) {
    TelemetryMetric.voltage => 'V',
    TelemetryMetric.current => 'A',
    TelemetryMetric.power => 'W',
    TelemetryMetric.temperature => '°C',
  };

  Color get color => switch (this) {
    TelemetryMetric.voltage => const Color(0xff3080c4),
    TelemetryMetric.current => const Color(0xffba7615),
    TelemetryMetric.power => const Color(0xffac64bf),
    TelemetryMetric.temperature => const Color(0xff168d79),
  };
}
