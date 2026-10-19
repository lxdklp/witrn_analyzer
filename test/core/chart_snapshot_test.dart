import 'package:flutter_test/flutter_test.dart';
import 'package:witrn_analyzer/core/models.dart';
import 'package:witrn_analyzer/data/chart_snapshot.dart';

void main() {
  test('axis conversion preserves constant values and negative current', () {
    final snapshot = ChartSnapshot.build([
      TelemetrySample(elapsedUs: 0, raw: [], voltage: 5, current: -2),
    ]);
    expect(snapshot.voltage.max, greaterThan(snapshot.voltage.min));
    expect(
      snapshot.current.valueAt(snapshot.current.normalize(-2)),
      closeTo(-2, 1e-9),
    );
  });
  test('downsampling preserves transient extrema and source timestamps', () {
    final samples = [
      for (var i = 0; i < 10000; i++)
        TelemetrySample(
          elapsedUs: i * 1000,
          raw: [],
          voltage: i == 5023 ? 20 : 5,
          current: i == 5024 ? -8 : 2,
        ),
    ];
    final snapshot = ChartSnapshot.build(samples, maxPoints: 300);
    expect(snapshot.samples.length, lessThanOrEqualTo(300));
    expect(snapshot.samples.any((s) => s.voltage == 20), isTrue);
    expect(snapshot.samples.any((s) => s.current == -8), isTrue);
    expect(snapshot.nearest(5.023)!.elapsedUs, 5023000);
  });
  test('power and temperature extrema survive decimation independently', () {
    final samples = [
      for (var i = 0; i < 10000; i++)
        TelemetrySample(
          elapsedUs: i * 1000,
          raw: [],
          voltage: i == 5023
              ? 20
              : i == 5025
              ? 10
              : 5,
          current: i == 5023
              ? 0.1
              : i == 5024
              ? 8
              : i == 5025
              ? 6
              : 2,
          temperature: i == 5026
              ? 80
              : i == 5027
              ? -10
              : 25,
        ),
    ];
    final snapshot = ChartSnapshot.build(samples, maxPoints: 300);
    expect(snapshot.samples.length, lessThanOrEqualTo(300));
    expect(snapshot.samples.any((s) => s.power == 60), isTrue);
    expect(snapshot.samples.any((s) => s.temperature == 80), isTrue);
    expect(snapshot.samples.any((s) => s.temperature == -10), isTrue);
    expect(
      snapshot.power.valueAt(snapshot.power.normalize(60)),
      closeTo(60, 1e-9),
    );
    expect(
      snapshot.temperature.valueAt(snapshot.temperature.normalize(-10)),
      closeTo(-10, 1e-9),
    );
    expect(snapshot.nearest(5.026)!.elapsedUs, 5026000);
  });

  test('gaps come from raw sampling, never from decimation intervals', () {
    final samples = [
      for (var i = 0; i < 6000; i++)
        TelemetrySample(elapsedUs: i * 100000, raw: [], voltage: 5, current: 2),
    ];
    final snapshot = ChartSnapshot.build(
      samples,
      windowSeconds: null,
      maxPoints: 60,
    );
    expect(snapshot.gaps, isEmpty);
    samples.add(
      TelemetrySample(elapsedUs: 700000000, raw: [], voltage: 5, current: 2),
    );
    expect(ChartSnapshot.build(samples, windowSeconds: null).gaps, [700000000]);
  });
}
