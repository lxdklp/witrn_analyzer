import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:witrn_analyzer/app.dart';
import 'package:witrn_analyzer/application/analyzer_view_model.dart';
import 'package:witrn_analyzer/data/capture_repository.dart';
import 'package:witrn_analyzer/ui/about_screen.dart';
import 'package:witrn_analyzer/ui/settings_screen.dart';

import '../fakes.dart';

void main() {
  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'WITRN Analyzer',
      packageName: 'test.witrn_analyzer',
      version: '2.3.4',
      buildNumber: '56',
      buildSignature: '',
    );
  });

  for (final size in [const Size(360, 640), const Size(1360, 920)]) {
    testWidgets('about navigation, installed version and licenses fit $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final model = AnalyzerViewModel(
        transport: FakeTransport(),
        repository: MemoryCaptureRepository(),
        files: FakeFiles(),
      );
      await tester.pumpWidget(WitrnAnalyzerApp(model: model));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('设置'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('关于'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('关于'));
      await tester.pumpAndSettle();
      expect(find.byType(AboutScreen), findsOneWidget);
      expect(find.text('2.3.4 (56)'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('第三方许可'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('第三方许可'));
      await tester.pumpAndSettle();
      expect(find.byType(LicensePage), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.byType(AboutScreen), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      model.dispose();
      await tester.pump();
    });
  }

  testWidgets(
    'project link uses external browser and failed launches offer a fallback',
    (tester) async {
      const channel = MethodChannel('plugins.flutter.io/url_launcher');
      final calls = <MethodCall>[];
      var succeeds = true;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return succeeds;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      await tester.pumpWidget(const MaterialApp(home: AboutScreen()));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('GitHub 项目主页'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('GitHub 项目主页'));
      await tester.pumpAndSettle();
      expect(calls.single.method, 'launch');
      final args = calls.single.arguments as Map<dynamic, dynamic>;
      expect(args['url'], AboutScreen.projectUrl);
      expect(args['useWebView'], isFalse);
      expect(args['useSafariVC'], isFalse);
      succeeds = false;
      await tester.tap(find.text('GitHub 项目主页'));
      await tester.pumpAndSettle();
      expect(find.text('复制链接'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
