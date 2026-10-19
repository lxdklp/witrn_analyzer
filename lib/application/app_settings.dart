import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../transport/hid_transport.dart';

/// Preferences are independent of the current capture session.
class AppSettings extends ChangeNotifier {
  AppSettings({this.preferences});

  static const defaultSeedColor = Color(0xff009e85);
  static const storageKey = 'appearance';
  static const hidReadRates = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
  static const defaultHidReadRateHz = 10;
  final SharedPreferencesAsync? preferences;
  ThemeMode _themeMode = ThemeMode.system;
  Color _seedColor = defaultSeedColor;
  bool _useDeviceColors = true;
  int _hidReadRateHz = defaultHidReadRateHz;
  int _usbVendorId = defaultUsbVendorId;
  int _usbProductId = defaultUsbProductId;
  bool _disposed = false;
  Future<void> _pendingSave = Future<void>.value();
  String? persistenceError;

  ThemeMode get themeMode => _themeMode;
  Color get seedColor => _seedColor;
  bool get useDeviceColors => _useDeviceColors;
  int get hidReadRateHz => _hidReadRateHz;
  int get usbVendorId => _usbVendorId;
  int get usbProductId => _usbProductId;

  static Future<AppSettings> load({SharedPreferencesAsync? preferences}) async {
    final settings = AppSettings(
      preferences: preferences ?? SharedPreferencesAsync(),
    );
    try {
      final raw = await settings.preferences!.getString(storageKey);
      if (raw == null) return settings;
      final data = jsonDecode(raw) as Map<String, dynamic>;
      settings._themeMode = ThemeMode.values.firstWhere(
        (mode) => mode.name == data['themeMode'],
        orElse: () => ThemeMode.system,
      );
      if (data['seedColor'] case final int color
          when color >= 0xff000000 && color <= 0xffffffff) {
        settings._seedColor = Color(color);
      }
      if (data['useDeviceColors'] case final bool enabled) {
        settings._useDeviceColors = enabled;
      }
      if (data['hidReadRateHz'] case final int rate
          when hidReadRates.contains(rate)) {
        settings._hidReadRateHz = rate;
      }
      if ((data['usbVendorId'], data['usbProductId'])
          case (final int vid, final int pid)
          when vid >= 0 && vid <= 0xffff && pid >= 0 && pid <= 0xffff) {
        settings._usbVendorId = vid;
        settings._usbProductId = pid;
      }
    } catch (_) {
      settings.persistenceError = '无法读取设置，已使用默认值。';
    }
    return settings;
  }

  Future<void> setThemeMode(ThemeMode value) {
    _themeMode = value;
    return _save();
  }

  Future<void> setSeedColor(Color value) {
    _seedColor = value;
    return _save();
  }

  Future<void> setUseDeviceColors(bool value) {
    _useDeviceColors = value;
    return _save();
  }

  Future<void> setHidReadRateHz(int value) {
    if (!hidReadRates.contains(value)) {
      throw ArgumentError.value(value, 'value', 'Unsupported HID read rate');
    }
    _hidReadRateHz = value;
    return _save();
  }

  Future<void> _save() {
    final data = jsonEncode({
      'themeMode': _themeMode.name,
      'seedColor': _seedColor.toARGB32(),
      'useDeviceColors': _useDeviceColors,
      'hidReadRateHz': _hidReadRateHz,
      'usbVendorId': _usbVendorId,
      'usbProductId': _usbProductId,
    });
    notifyListeners();
    // Serialize writes so rapid selections cannot restore an older preference.
    return _pendingSave = _pendingSave.then((_) async {
      try {
        await preferences?.setString(storageKey, data);
        persistenceError = null;
      } catch (_) {
        persistenceError = '设置已生效，但无法保存；重启后可能恢复为之前的设置。';
      }
      if (!_disposed) notifyListeners();
    });
  }

  Future<void> setUsbDeviceIds({
    required int vendorId,
    required int productId,
  }) {
    RangeError.checkValueInInterval(vendorId, 0, 0xffff, 'vendorId');
    RangeError.checkValueInInterval(productId, 0, 0xffff, 'productId');
    _usbVendorId = vendorId;
    _usbProductId = productId;
    return _save();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
