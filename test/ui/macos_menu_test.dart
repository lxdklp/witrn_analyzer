import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:witrn_analyzer/app.dart';
import 'package:witrn_analyzer/application/analyzer_view_model.dart';
import 'package:witrn_analyzer/core/models.dart';
import 'package:witrn_analyzer/data/capture_file_service.dart';
import 'package:witrn_analyzer/data/capture_repository.dart';

import '../fakes.dart';

void main() {
  testWidgets('macOS menu actions follow navigation and capture state', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1360, 920);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const channel = MethodChannel('witrn_analyzer/menu');
    final states = <Map<String, bool>>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      if (call.method == 'setState') {
        states.add(Map<String, bool>.from(call.arguments as Map));
      }
      return null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );

    Future<void> command(String action) {
      final done = Completer<void>();
      tester.binding.channelBuffers.push(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(
          MethodCall('invoke', action),
        ),
        (reply) {
          try {
            const StandardMethodCodec().decodeEnvelope(reply!);
            done.complete();
          } catch (error, stack) {
            done.completeError(error, stack);
          }
        },
      );
      return done.future;
    }

    // Native callbacks run in the binding's test zone. Pump while worker-isolate
    // replies arrive, rather than awaiting a fake-zone future inside runAsync.
    Future<void> finish(Future<void> pending) async {
      var completed = false;
      final result = pending.whenComplete(() => completed = true);
      for (var i = 0; i < 300 && !completed; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 10));
      }
      expect(completed, isTrue, reason: 'Menu command did not complete');
      await result;
    }

    final transport = FakeTransport();
    final files = FakeFiles();
    final repository = MemoryCaptureRepository();
    final model = AnalyzerViewModel(
      transport: transport,
      repository: repository,
      files: files,
    );
    await tester.pumpWidget(WitrnAnalyzerApp(model: model));
    await tester.pumpAndSettle();
    expect(states.last['settings'], isTrue);
    expect(states.last['importMessages'], isTrue);
    expect(states.last['exportMessages'], isFalse);
    expect(states.last['importChart'], isTrue);
    expect(states.last['exportChart'], isFalse);
    expect(states.last['record'], isFalse);

    await command('settings');
    await tester.pumpAndSettle();
    expect(find.text('USB 连接'), findsOneWidget);
    expect(states.last['settings'], isFalse);
    await command('settings');
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('USB 连接'), findsNothing);
    expect(states.last['settings'], isTrue);

    final diagnostic = command('diagnostics');
    await tester.pumpAndSettle();
    expect(find.text('采集与导入诊断'), findsOneWidget);
    expect(states.last['importMessages'], isFalse);
    await command('settings');
    expect(find.text('USB 连接'), findsNothing);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    await diagnostic;

    await command('refresh');
    await finish(command('connectAndStart'));
    await tester.runAsync(() async {
      expect(states.last['connecting'], isTrue);
      expect(states.last['disconnect'], isTrue);
      transport.emit(parseHex('FE07E0A1112C910100'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
    expect(model.recording, isTrue);
    expect(states.last['recording'], isTrue);
    expect(states.last['importMessages'], isFalse);
    expect(states.last['exportMessages'], isTrue);
    expect(states.last['refresh'], isFalse);
    await command('record');
    await tester.pumpAndSettle();
    expect(model.recording, isFalse);
    expect(states.last['importMessages'], isTrue);
    await command('record');
    await tester.pumpAndSettle();
    expect(model.recording, isTrue);
    await command('importMessages');
    expect(model.recording, isTrue);
    await finish(command('exportMessages'));
    expect(files.saved, isNotNull);
    await finish(command('disconnect'));
    await tester.pumpAndSettle();
    expect(states.last['disconnect'], isFalse);
    expect(states.last['record'], isFalse);

    await command('follow');
    await tester.pumpAndSettle();
    expect(model.followLatest, isFalse);
    expect(states.last['following'], isFalse);
    final count = states.length;
    model.setFollow(false);
    await tester.pump();
    expect(states.length, count);

    final clearing = command('newSession');
    await tester.pumpAndSettle();
    expect(find.text('新建采集会话？'), findsOneWidget);
    expect(states.last['newSession'], isFalse);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await clearing;
    expect(model.records, isNotEmpty);
    final confirmed = command('newSession');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '新建会话'));
    await finish(confirmed);
    await tester.pumpAndSettle();
    expect(model.records, isEmpty);

    files.picked = CaptureFile(
      'menu.csv',
      Uint8List.fromList(utf8.encode('Raw\nFE07E0A1112C910100')),
    );
    await finish(command('importMessages'));
    await tester.pumpAndSettle();
    expect(model.fileName, 'menu.csv');
    expect(model.records, hasLength(1));
    files.picked = CaptureFile(
      'chart.csv',
      Uint8List.fromList(
        utf8.encode(
          'elapsed_us,voltage_v,current_a,power_w,temperature_c\n0,5,2,10,25\n1000000,9,2,18,26',
        ),
      ),
    );
    await finish(command('importChart'));
    await tester.pumpAndSettle();
    expect(model.samples, hasLength(2));
    expect(model.records, hasLength(1));
    expect(files.pickTitle, '导入图表');
    expect(states.last['exportChart'], isTrue);
    await finish(command('exportChart'));
    expect(files.saveTitle, '导出图表');
    expect(utf8.decode(files.saved!), contains('elapsed_us'));

    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(model.shutdown);
    model.dispose();
  }, variant: TargetPlatformVariant({TargetPlatform.macOS}));
}
