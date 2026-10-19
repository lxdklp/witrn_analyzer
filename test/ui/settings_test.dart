import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:witrn_analyzer/app.dart';
import 'package:witrn_analyzer/application/analyzer_view_model.dart';
import 'package:witrn_analyzer/application/app_settings.dart';
import 'package:witrn_analyzer/core/models.dart';
import 'package:witrn_analyzer/data/capture_repository.dart';
import 'package:witrn_analyzer/transport/hid_transport.dart';
import 'package:witrn_analyzer/ui/settings_screen.dart';

import '../fakes.dart';

void main() {
  late AnalyzerViewModel model;
  late AppSettings settings;

  setUp(() {
    model = AnalyzerViewModel(
      transport: FakeTransport(),
      repository: MemoryCaptureRepository(),
      files: FakeFiles(),
    );
    settings = AppSettings();
  });

  tearDown(() {
    model.dispose();
    settings.dispose();
    debugDefaultTargetPlatformOverride = null;
  });

  ThemeData currentTheme(WidgetTester tester) =>
      Theme.of(tester.element(find.byType(SettingsScreen)));

  Future<void> openSettings(WidgetTester tester) async {
    await tester.pumpWidget(WitrnAnalyzerApp(model: model, settings: settings));
    await tester.pumpAndSettle();
    expect(find.byTooltip('切换明暗主题'), findsNothing);
    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
  }

  testWidgets(
    'follows device brightness and applies explicit appearance and palette immediately',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await openSettings(tester);
      expect(currentTheme(tester).brightness, Brightness.dark);
      expect(find.text('主题色跟随设备'), findsNothing);
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      await tester.pumpAndSettle();
      expect(currentTheme(tester).brightness, Brightness.light);
      await tester.tap(find.text('深色'));
      await tester.pumpAndSettle();
      expect(currentTheme(tester).brightness, Brightness.dark);
      await tester.ensureVisible(find.text('紫色'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, '紫色'));
      await tester.pumpAndSettle();
      expect(
        currentTheme(tester).colorScheme,
        ColorScheme.fromSeed(
          seedColor: const Color(0xff6750a4),
          brightness: Brightness.dark,
        ),
      );
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.byTooltip('设置'), findsOneWidget);
      expect(find.byType(BackButton), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets(
    'Android dynamic colors toggle and refresh preserve settings navigation',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      var palette = Int64List.fromList(List<int>.filled(65, 0xff3366aa));
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        DynamicColorPlugin.channel,
        (call) async => call.method == 'getCorePalette' ? palette : null,
      );
      addTearDown(
        () => messenger.setMockMethodCallHandler(
          DynamicColorPlugin.channel,
          null,
        ),
      );
      await openSettings(tester);
      expect(settings.useDeviceColors, isTrue);
      expect(currentTheme(tester).colorScheme.primary, const Color(0xff3366aa));
      final deviceSwitch = find.widgetWithText(SwitchListTile, '主题色跟随设备');
      await tester.ensureVisible(deviceSwitch);
      await tester.pumpAndSettle();
      await tester.tap(deviceSwitch);
      await tester.pumpAndSettle();
      expect(
        currentTheme(tester).colorScheme,
        ColorScheme.fromSeed(seedColor: AppSettings.defaultSeedColor),
      );
      await tester.ensureVisible(find.text('紫色'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, '紫色'));
      await tester.pumpAndSettle();
      expect(settings.seedColor, const Color(0xff6750a4));
      await tester.ensureVisible(deviceSwitch);
      await tester.pumpAndSettle();
      await tester.tap(deviceSwitch);
      await tester.pumpAndSettle();
      expect(currentTheme(tester).colorScheme.primary, const Color(0xff3366aa));
      palette = Int64List.fromList(List<int>.filled(65, 0xffaa3366));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(currentTheme(tester).colorScheme.primary, const Color(0xffaa3366));
      expect(settings.seedColor, const Color(0xff6750a4));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    },
  );

  for (final size in [const Size(360, 640), const Size(1360, 920)]) {
    testWidgets('settings fit $size and parser settings honor session lock', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await openSettings(tester);
      // A device without a dynamic palette falls back to the green seed.
      expect(
        currentTheme(tester).colorScheme,
        ColorScheme.fromSeed(seedColor: AppSettings.defaultSeedColor),
      );
      final profile = find.byType(DropdownButtonFormField<DecodeProfile>);
      await tester.scrollUntilVisible(
        profile,
        250,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      await tester.tap(profile);
      await tester.pumpAndSettle();
      await tester.tap(find.text('标准 USB PD 位宽').last);
      await tester.pumpAndSettle();
      expect(model.profile, DecodeProfile.standard);
      final layout = find.byType(DropdownButtonFormField<ReportLayout>);
      await tester.ensureVisible(layout);
      await tester.pumpAndSettle();
      await tester.tap(layout);
      await tester.pumpAndSettle();
      await tester.tap(find.text('64 字节 WITRN 原始报告').last);
      await tester.pumpAndSettle();
      expect(model.reportLayout, ReportLayout.raw64);
      final crc = find.widgetWithText(SwitchListTile, '校验存在的 CRC');
      await tester.ensureVisible(crc);
      await tester.pumpAndSettle();
      await tester.tap(crc);
      await tester.pumpAndSettle();
      expect(model.verifyCrc, isTrue);
      model.connection = ConnectionPhase.connected;
      model.setFilters(query: '');
      await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(crc).onChanged, isNull);
      await tester.ensureVisible(profile);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<DropdownButtonFormField<DecodeProfile>>(profile)
            .onChanged,
        isNull,
      );
      // Appearance stays editable while capture settings are locked.
      await tester.scrollUntilVisible(
        find.text('深色'),
        -250,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('深色'));
      await tester.pumpAndSettle();
      expect(currentTheme(tester).brightness, Brightness.dark);
      expect(tester.takeException(), isNull);
      model.connection = ConnectionPhase.disconnected;
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    });
  }
}
