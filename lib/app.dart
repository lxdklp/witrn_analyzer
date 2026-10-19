import 'dart:async';

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'application/analyzer_view_model.dart';
import 'application/app_settings.dart';
import 'data/capture_file_service.dart';
import 'data/capture_repository.dart';
import 'transport/hid_tool_transport.dart';
import 'ui/analyzer_screen.dart';
import 'ui/about_screen.dart';
import 'ui/settings_screen.dart';
import 'ui/macos_menu_controller.dart';

class WitrnAnalyzerApp extends StatefulWidget {
  const WitrnAnalyzerApp({super.key, this.model, this.settings});
  final AnalyzerViewModel? model;
  final AppSettings? settings;
  @override
  State<WitrnAnalyzerApp> createState() => _WitrnAnalyzerAppState();
}

class _WitrnAnalyzerAppState extends State<WitrnAnalyzerApp> {
  late final AnalyzerViewModel _model =
      widget.model ??
      AnalyzerViewModel(
        transport: HidToolTransport(),
        repository: MemoryCaptureRepository(),
        files: NativeCaptureFileService(),
      );
  late final AppSettings _settings = widget.settings ?? AppSettings();
  late final AppLifecycleListener _lifecycle;
  int _dynamicColorRevision = 0;
  final _navigatorKey = GlobalKey<NavigatorState>();
  final _menuObserver = MenuNavigatorObserver();
  MacosMenuController? _macosMenu;
  bool get _android =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  void initState() {
    super.initState();
    _settings.addListener(_applyDeviceSettings);
    _applyDeviceSettings();
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.macOS) {
      _macosMenu = MacosMenuController(
        model: _model,
        navigatorKey: _navigatorKey,
        observer: _menuObserver,
      );
    }
    _lifecycle = AppLifecycleListener(
      // The plugin reads colors once; refresh after returning from system settings.
      onResume: () {
        if (_android && mounted) setState(() => _dynamicColorRevision++);
      },
    );
  }

  void _applyDeviceSettings() {
    unawaited(_model.setHidReadRate(_settings.hidReadRateHz));
    _model.setUsbDeviceIds(
      vendorId: _settings.usbVendorId,
      productId: _settings.usbProductId,
    );
  }

  @override
  void dispose() {
    _settings.removeListener(_applyDeviceSettings);
    _macosMenu?.dispose();
    _menuObserver.dispose();
    _lifecycle.dispose();
    if (widget.model == null) _model.dispose();
    if (widget.settings == null) _settings.dispose();
    super.dispose();
  }

  ThemeData _theme(Brightness brightness, ColorScheme? dynamicScheme) =>
      ThemeData(
        useMaterial3: true,
        colorScheme:
            _android && _settings.useDeviceColors && dynamicScheme != null
            ? dynamicScheme
            : ColorScheme.fromSeed(
                seedColor: _settings.seedColor,
                brightness: brightness,
              ),
        fontFamilyFallback: const [
          'PingFang SC',
          'Microsoft YaHei',
          'Noto Sans CJK SC',
        ],
        inputDecorationTheme: const InputDecorationTheme(
          filled: true,
          border: OutlineInputBorder(),
        ),
        tooltipTheme: const TooltipThemeData(
          waitDuration: Duration(milliseconds: 450),
        ),
      );

  @override
  Widget build(BuildContext context) => DynamicColorBuilder(
    // A global key below preserves navigation and capture state during refresh.
    key: ValueKey(_dynamicColorRevision),
    builder: (lightDynamic, darkDynamic) => ListenableBuilder(
      listenable: _settings,
      builder: (context, _) => MaterialApp(
        key: _appKey,
        navigatorKey: _navigatorKey,
        navigatorObservers: [_menuObserver],
        title: 'WITRN PD Analyzer',
        debugShowCheckedModeBanner: false,
        theme: _theme(Brightness.light, lightDynamic),
        darkTheme: _theme(Brightness.dark, darkDynamic),
        themeMode: _settings.themeMode,
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        routes: {
          '/about': (_) => const AboutScreen(),
          '/settings': (_) =>
              SettingsScreen(model: _model, settings: _settings),
        },
        home: AnalyzerScreen(model: _model),
      ),
    ),
  );

  final GlobalKey _appKey = GlobalKey();
}
