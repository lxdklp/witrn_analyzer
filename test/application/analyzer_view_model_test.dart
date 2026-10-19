import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:witrn_analyzer/application/analyzer_view_model.dart';
import 'package:witrn_analyzer/core/models.dart';
import 'package:witrn_analyzer/data/capture_repository.dart';
import 'package:witrn_analyzer/data/csv_capture_codec.dart';

import '../fakes.dart';

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 80));
void main() {
  late FakeTransport transport;
  late FakeFiles files;
  late AnalyzerViewModel model;
  setUp(() {
    transport = FakeTransport();
    files = FakeFiles();
    model = AnalyzerViewModel(
      transport: transport,
      repository: MemoryCaptureRepository(recordLimit: 20),
      files: files,
      connectionTimeout: const Duration(milliseconds: 180),
    );
  });
  tearDown(() async {
    await model.shutdown();
    model.dispose();
  });
  test(
    'first valid packet starts recording; pause freezes PD and telemetry',
    () async {
      await model.connect();
      expect(model.connection, ConnectionPhase.connecting);
      transport.emit(parseHex('FE07E0A1112C910100'));
      await settle();
      expect(model.connected, isTrue);
      expect(model.recording, isTrue);
      expect(model.records, hasLength(1));
      transport.emit(parseHex('FE07E082122C210310'));
      await settle();
      expect(model.records.last.message.request!.current, 2);
      final telemetry = Uint8List(64)..[0] = 0xff;
      final data = ByteData.sublistView(telemetry);
      data.setFloat32(46, 5, Endian.little);
      transport.emit(telemetry);
      await settle();
      expect(model.latestTelemetry!.voltage, 5);
      expect(model.samples, hasLength(1));
      model.pause();
      data.setFloat32(46, 9, Endian.little);
      transport.emit(telemetry);
      transport.emit(parseHex('FE03E08100'));
      await settle();
      expect(model.latestTelemetry!.voltage, 5);
      expect(model.samples, hasLength(1));
      expect(model.records, hasLength(2));
      expect(model.pausedReports, 2);
      model.start();
      data.setFloat32(46, 12, Endian.little);
      transport.emit(telemetry);
      await settle();
      expect(model.latestTelemetry!.voltage, 12);
      expect(model.samples, hasLength(2));
      await model.disconnect();
      expect(transport.isOpen, isFalse);
      expect(model.records, hasLength(2));
    },
  );
  test(
    'F5 captures first valid packet and filters never affect export',
    () async {
      await model.connect();
      transport.emit(parseHex('FE03E08100'));
      transport.emit(parseHex('FE07E0A1112C910100'));
      await settle();
      expect(model.recording, isTrue);
      expect(model.records, hasLength(2));
      expect(model.visibleRecords, hasLength(1));
      await model.exportCsv();
      expect(
        const CsvCaptureCodec().decode(files.saved!).records,
        hasLength(2),
      );
      model.setFilters(goodCrc: false);
      expect(model.visibleRecords, hasLength(2));
      model.setFilters(query: 'Source');
      expect(model.visibleRecords, hasLength(1));
    },
  );
  test(
    'connection failure, first-packet timeout and hot unplug close ownership',
    () async {
      transport.openError = StateError('permission denied');
      await model.connect();
      expect(model.connection, ConnectionPhase.failed);
      expect(model.error, contains('permission denied'));
      transport.openError = null;
      await model.connect();
      await Future<void>.delayed(const Duration(milliseconds: 260));
      expect(model.connection, ConnectionPhase.failed);
      expect(transport.isOpen, isFalse);
      await model.connect();
      transport.emit(parseHex('FE03E08100'));
      await settle();
      transport.controller.addError(StateError('unplugged'));
      await settle();
      expect(model.connection, ConnectionPhase.failed);
      expect(transport.isOpen, isFalse);
    },
  );
  test('failed import preserves session, successful import isolates context and disconnects', () async {
    await model.importBytes(
      Uint8List.fromList(utf8.encode('Raw\nFE07E0A1112C910100')),
      'existing.csv',
    );
    final count = model.records.length;
    await model.importBytes(
      Uint8List.fromList(utf8.encode('bad\ninvalid')),
      'bad.csv',
    );
    expect(model.records.length, count);
    expect(model.source, ContentSource.imported);
    await model.importBytes(
      Uint8List.fromList(utf8.encode('Raw\nFE07E082122C210310')),
      'request.csv',
    );
    expect(model.records, hasLength(1));
    expect(model.source, ContentSource.imported);
    expect(
      model.records.single.message.diagnostics.map((d) => d.code),
      contains('missingContext'),
    );
    expect(model.samples, isEmpty);
  });
  test(
    'clear establishes fresh context; late frames cannot restore old records',
    () async {
      await model.connect();
      transport.emit(parseHex('FE07E0A1112C910100'));
      await settle();
      await model.clearSession();
      expect(model.recording, isTrue);
      transport.emit(parseHex('FE07E082122C210310'));
      await settle();
      expect(model.records, hasLength(1));
      expect(model.records.single.id, 1);
      expect(model.records.single.message.request!.capability, isNull);
    },
  );
  test('capacity pauses recording explicitly', () async {
    await model.connect();
    for (var i = 0; i < 25; i++) {
      transport.emit(parseHex('FE03E08100'));
    }
    await settle();
    expect(model.records.length, 20);
    expect(model.recording, isFalse);
    expect(model.droppedReports, 5);
  });
}
