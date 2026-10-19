import 'dart:collection';

import '../core/models.dart';

abstract interface class CaptureRepository {
  List<CaptureRecord> get records;
  List<TelemetrySample> get samples;
  List<Diagnostic> get diagnostics;
  int get revision;
  int get telemetryRevision;
  bool addRecord(CaptureRecord record);
  void addSample(TelemetrySample sample);
  void addDiagnostic(Diagnostic diagnostic);
  void replace(List<CaptureRecord> records, List<Diagnostic> diagnostics);
  void replaceSamples(List<TelemetrySample> samples);
  void clear();
}

final class MemoryCaptureRepository implements CaptureRepository {
  MemoryCaptureRepository({
    this.recordLimit = 100000,
    this.sampleLimit = 60000,
  });
  final int recordLimit, sampleLimit;
  final List<CaptureRecord> _records = [];
  final Queue<TelemetrySample> _samples = Queue();
  final List<Diagnostic> _diagnostics = [];
  @override
  int revision = 0;
  @override
  int telemetryRevision = 0;
  @override
  List<CaptureRecord> get records => UnmodifiableListView(_records);
  @override
  List<TelemetrySample> get samples => List.unmodifiable(_samples);
  @override
  List<Diagnostic> get diagnostics => UnmodifiableListView(_diagnostics);
  @override
  bool addRecord(CaptureRecord record) {
    if (_records.length >= recordLimit) return false;
    _records.add(record);
    revision++;
    return true;
  }

  @override
  void addSample(TelemetrySample sample) {
    if (_samples.length >= sampleLimit) _samples.removeFirst();
    _samples.addLast(sample);
    telemetryRevision++;
  }

  @override
  void addDiagnostic(Diagnostic diagnostic) {
    if (_diagnostics.length >= 500) _diagnostics.removeAt(0);
    _diagnostics.add(diagnostic);
  }

  @override
  void replace(List<CaptureRecord> records, List<Diagnostic> diagnostics) {
    _records.clear();
    _diagnostics.clear();
    _records.addAll(records);
    _diagnostics.addAll(diagnostics.take(500));
    revision++;
  }

  @override
  void replaceSamples(List<TelemetrySample> samples) {
    if (samples.length > sampleLimit) {
      throw FormatException('图表超过 $sampleLimit 条采样，请拆分后导入');
    }
    _samples.clear();
    _samples.addAll(samples);
    telemetryRevision++;
  }

  @override
  void clear() {
    _records.clear();
    _samples.clear();
    _diagnostics.clear();
    revision++;
    telemetryRevision++;
  }
}
