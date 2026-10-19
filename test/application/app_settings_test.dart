import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:witrn_analyzer/application/app_settings.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  test('defaults and rapid appearance changes survive reload', () async {
    final settings = await AppSettings.load();
    expect(settings.themeMode, ThemeMode.system);
    expect(settings.seedColor, AppSettings.defaultSeedColor);
    expect(settings.useDeviceColors, isTrue);
    expect(settings.hidReadRateHz, 10);
    expect(settings.usbVendorId, 0x0716);
    expect(settings.usbProductId, 0x5060);
    await Future.wait([
      settings.setThemeMode(ThemeMode.dark),
      settings.setThemeMode(ThemeMode.light),
      settings.setSeedColor(const Color(0xff6750a4)),
      settings.setUseDeviceColors(false),
      settings.setHidReadRateHz(3),
      settings.setHidReadRateHz(7),
      settings.setUsbDeviceIds(vendorId: 0x1234, productId: 0xabcd),
    ]);
    final restored = await AppSettings.load();
    expect(restored.themeMode, ThemeMode.light);
    expect(restored.seedColor, const Color(0xff6750a4));
    expect(restored.useDeviceColors, isFalse);
    expect(restored.hidReadRateHz, 7);
    expect(restored.usbVendorId, 0x1234);
    expect(restored.usbProductId, 0xabcd);
    expect(restored.persistenceError, isNull);
    settings.dispose();
    restored.dispose();
  });

  test(
    'USB identifiers validate as a pair and old preferences retain defaults',
    () async {
      final preferences = SharedPreferencesAsync();
      for (final raw in [
        '{}',
        '{"usbVendorId":-1,"usbProductId":1}',
        '{"usbVendorId":1,"usbProductId":65536}',
        '{"usbVendorId":"1234","usbProductId":1}',
        '{"usbVendorId":4660}',
      ]) {
        await preferences.setString(AppSettings.storageKey, raw);
        final settings = await AppSettings.load();
        expect((settings.usbVendorId, settings.usbProductId), (0x0716, 0x5060));
        expect(
          () => settings.setUsbDeviceIds(vendorId: 0x1234, productId: 65536),
          throwsRangeError,
        );
        expect((settings.usbVendorId, settings.usbProductId), (0x0716, 0x5060));
        settings.dispose();
      }
      final settings = await AppSettings.load();
      await settings.setUsbDeviceIds(vendorId: 0, productId: 0xffff);
      final restored = await AppSettings.load();
      expect((restored.usbVendorId, restored.usbProductId), (0, 0xffff));
      settings.dispose();
      restored.dispose();
    },
  );

  test('old and invalid read rate preferences keep the default', () async {
    final preferences = SharedPreferencesAsync();
    for (final raw in [
      '{"themeMode":"dark"}',
      '{"hidReadRateHz":0}',
      '{"hidReadRateHz":11}',
      '{"hidReadRateHz":50}',
      '{"hidReadRateHz":1000}',
      '{"hidReadRateHz":"100"}',
    ]) {
      await preferences.setString(AppSettings.storageKey, raw);
      final settings = await AppSettings.load();
      expect(settings.hidReadRateHz, 10);
      expect(() => settings.setHidReadRateHz(0), throwsArgumentError);
      expect(() => settings.setHidReadRateHz(11), throwsArgumentError);
      settings.dispose();
    }
  });

  test(
    'invalid stored preferences fall back without blocking startup',
    () async {
      final preferences = SharedPreferencesAsync();
      await preferences.setString(AppSettings.storageKey, '{broken json');
      final settings = await AppSettings.load();
      expect(settings.themeMode, ThemeMode.system);
      expect(settings.seedColor, AppSettings.defaultSeedColor);
      expect(settings.persistenceError, isNotNull);
      await settings.setThemeMode(ThemeMode.dark);
      expect(settings.persistenceError, isNull);
      final restored = await AppSettings.load();
      expect(restored.themeMode, ThemeMode.dark);
      settings.dispose();
      restored.dispose();
    },
  );
}
