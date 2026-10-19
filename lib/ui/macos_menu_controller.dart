import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../application/analyzer_view_model.dart';
import 'session_actions.dart';

class MenuNavigatorObserver extends NavigatorObserver with ChangeNotifier {
  final List<Route<dynamic>> _routes = [];
  Route<dynamic>? get currentRoute => _routes.lastOrNull;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.add(route);
    notifyListeners();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    notifyListeners();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    notifyListeners();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final index = oldRoute == null ? -1 : _routes.indexOf(oldRoute);
    if (index >= 0) {
      if (newRoute == null) {
        _routes.removeAt(index);
      } else {
        _routes[index] = newRoute;
      }
    }
    notifyListeners();
  }
}

/// Updates native AppKit menus without replacing the system responder chain.
class MacosMenuController {
  MacosMenuController({
    required this.model,
    required this.navigatorKey,
    required this.observer,
  }) {
    _channel.setMethodCallHandler(_handleMenu);
    model.addListener(_sync);
    observer.addListener(_sync);
    _sync();
  }

  static const _channel = MethodChannel('witrn_analyzer/menu');
  final AnalyzerViewModel model;
  final GlobalKey<NavigatorState> navigatorKey;
  final MenuNavigatorObserver observer;
  Map<String, bool>? _lastState;

  Map<String, bool> get _state {
    final ready = observer.currentRoute is PageRoute;
    final idle = ready && !model.busy && !model.transitioning;
    return {
      'settings': ready && observer.currentRoute?.settings.name != '/settings',
      'newSession': idle,
      'importChart': ready && model.canImport,
      'exportChart': ready && model.canExportChart,
      'importMessages': ready && model.canImport,
      'exportMessages': ready && !model.busy && model.records.isNotEmpty,
      'refresh': idle && !model.connected && !model.scanning,
      'connect': idle && !model.connected && !model.scanning,
      'connectAndStart': idle && !model.scanning && !model.recording,
      'disconnect':
          ready &&
          !model.busy &&
          (model.connected || model.connection == ConnectionPhase.connecting),
      'record': idle && model.connected,
      'follow': ready && !model.busy,
      'diagnostics': ready,
      'recording': model.recording,
      'connecting': model.connection == ConnectionPhase.connecting,
      'following': model.followLatest,
    };
  }

  void _sync() {
    final state = _state;
    // Telemetry updates don't need to rebuild an unchanged native menu.
    if (mapEquals(state, _lastState)) return;
    _lastState = state;
    unawaited(_sendState(state));
  }

  Future<void> _sendState(Map<String, bool> state) async {
    try {
      await _channel.invokeMethod<void>('setState', state);
    } on MissingPluginException {
      // Allows widget previews and test hosts without the macOS runner.
    }
  }

  Future<void> _handleMenu(MethodCall call) async {
    if (call.method != 'invoke') return;
    final action = call.arguments as String;
    // Recheck here: the app may have changed since AppKit validated the item.
    if (_state[action] != true) return;
    final navigator = navigatorKey.currentState;
    if (navigator == null) return;
    switch (action) {
      case 'settings':
        unawaited(navigator.pushNamed('/settings'));
      case 'newSession':
        await confirmNewSession(navigator.context, model);
      case 'importChart':
        await model.importChart();
      case 'exportChart':
        await model.exportChart();
      case 'importMessages':
        await model.importCsv();
      case 'exportMessages':
        await model.exportCsv();
      case 'refresh':
        await model.refreshDevices();
      case 'connect':
        await model.connect();
      case 'connectAndStart':
        await model.connect();
      case 'disconnect':
        await model.disconnect();
      case 'record':
        model.recording ? model.pause() : model.start();
      case 'follow':
        model.setFollow(!model.followLatest);
      case 'diagnostics':
        await showCaptureDiagnostics(navigator.context, model);
    }
  }

  void dispose() {
    model.removeListener(_sync);
    observer.removeListener(_sync);
    _channel.setMethodCallHandler(null);
  }
}
