import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../application/analyzer_view_model.dart';
import '../application/app_settings.dart';
import '../core/models.dart';
import '../transport/hid_transport.dart';
import 'usb_connection_settings.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.model,
    required this.settings,
  });

  final AnalyzerViewModel model;
  final AppSettings settings;

  static const _palette = [
    ('翡翠绿', AppSettings.defaultSeedColor),
    ('森林绿', Color(0xff386a20)),
    ('青色', Color(0xff006874)),
    ('海蓝', Color(0xff0061a4)),
    ('靛蓝', Color(0xff4355b9)),
    ('紫色', Color(0xff6750a4)),
    ('玫瑰', Color(0xff984061)),
    ('红色', Color(0xffba1a1a)),
    ('橙色', Color(0xff9b4600)),
    ('琥珀', Color(0xff805600)),
    ('棕色', Color(0xff795548)),
    ('岩灰', Color(0xff5f6368)),
  ];

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([model, settings]),
    builder: (context, _) => Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 960;
            final themeSection = _section(
              context,
              '主题设置',
              Icons.palette_outlined,
              _themeCard(context, wide: wide),
            );
            final leftSections = [
              themeSection,
              const SizedBox(height: 24),
              _section(
                context,
                'USB 连接',
                Icons.usb,
                UsbConnectionSettings(
                  settings: settings,
                  enabled: model.canConfigureUsb,
                ),
              ),
              const SizedBox(height: 24),
              _section(context, '采样设置', Icons.speed, _samplingCard(context)),
            ];
            final rightSections = [
              _section(context, '解析与设备设置', Icons.tune, _parserCard(context)),
              const SizedBox(height: 24),
              _section(
                context,
                '快捷键',
                Icons.keyboard_outlined,
                _shortcutsCard(),
              ),
              const SizedBox(height: 24),
              Card.filled(
                margin: EdgeInsets.zero,
                clipBehavior: Clip.antiAlias,
                child: ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: const Text('关于'),
                  subtitle: const Text('应用信息、项目链接与开源许可'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).pushNamed('/about'),
                ),
              ),
              if (model.transport.descriptor case final descriptor?) ...[
                const SizedBox(height: 24),
                _section(
                  context,
                  '当前 HID 描述符',
                  Icons.usb,
                  Card.filled(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: SelectableText(
                        hexBytes(descriptor),
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(fontFamily: 'monospace'),
                      ),
                    ),
                  ),
                ),
              ],
            ];
            return SingleChildScrollView(
              padding: EdgeInsets.all(wide ? 24 : 16),
              child: wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: leftSections,
                          ),
                        ),
                        const SizedBox(width: 24),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: rightSections,
                          ),
                        ),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ...leftSections,
                        const SizedBox(height: 24),
                        ...rightSections,
                      ],
                    ),
            );
          },
        ),
      ),
    ),
  );

  Widget _section(
    BuildContext context,
    String title,
    IconData icon,
    Widget card,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [_sectionTitle(context, title, icon), card],
  );

  Widget _themeCard(BuildContext context, {required bool wide}) {
    final theme = Theme.of(context);
    final android = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    final deviceColors = android && settings.useDeviceColors;
    return Card.filled(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ListTile(title: Text('外观'), subtitle: Text('默认跟随设备的深色或浅色模式')),
            if (wide && MediaQuery.textScalerOf(context).scale(14) <= 20)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: SegmentedButton<ThemeMode>(
                  expandedInsets: EdgeInsets.zero,
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: ThemeMode.system,
                      icon: Icon(Icons.brightness_auto),
                      label: Text('跟随设备'),
                    ),
                    ButtonSegment(
                      value: ThemeMode.light,
                      icon: Icon(Icons.light_mode_outlined),
                      label: Text('浅色'),
                    ),
                    ButtonSegment(
                      value: ThemeMode.dark,
                      icon: Icon(Icons.dark_mode_outlined),
                      label: Text('深色'),
                    ),
                  ],
                  selected: {settings.themeMode},
                  onSelectionChanged: (values) =>
                      unawaited(settings.setThemeMode(values.single)),
                ),
              )
            else
              RadioGroup<ThemeMode>(
                groupValue: settings.themeMode,
                onChanged: (value) {
                  if (value != null) {
                    unawaited(settings.setThemeMode(value));
                  }
                },
                child: const Column(
                  children: [
                    RadioListTile(value: ThemeMode.system, title: Text('跟随设备')),
                    RadioListTile(value: ThemeMode.light, title: Text('浅色')),
                    RadioListTile(value: ThemeMode.dark, title: Text('深色')),
                  ],
                ),
              ),
            const Divider(),
            if (android) ...[
              SwitchListTile(
                title: const Text('主题色跟随设备'),
                subtitle: const Text('需要 Android 12 +'),
                value: settings.useDeviceColors,
                onChanged: (value) =>
                    unawaited(settings.setUseDeviceColors(value)),
              ),
              const Divider(),
            ],
            ListTile(
              title: const Text('主题调色盘'),
              subtitle: Text(
                deviceColors
                    ? '系统动态色不可用时使用已选主题色；关闭开关后可修改。'
                    : '选择主题色，自动生成整套深浅配色。',
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final (name, seed) in _palette)
                    Theme(
                      data: theme.copyWith(
                        colorScheme: ColorScheme.fromSeed(
                          seedColor: seed,
                          brightness: theme.brightness,
                        ),
                      ),
                      child: ChoiceChip(
                        avatar: Icon(Icons.circle, color: seed, size: 18),
                        label: Text(name),
                        selected: settings.seedColor == seed,
                        onSelected: deviceColors
                            ? null
                            : (_) => unawaited(settings.setSeedColor(seed)),
                      ),
                    ),
                ],
              ),
            ),
            if (settings.persistenceError case final error?)
              ListTile(
                leading: Icon(
                  Icons.error_outline,
                  color: theme.colorScheme.error,
                ),
                title: Text(error),
              ),
          ],
        ),
      ),
    );
  }

  Widget _samplingCard(BuildContext context) {
    final rate = settings.hidReadRateHz;
    final intervalMs = 1000 / rate;
    return Card.filled(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('USB HID 读取频率', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Text(
              '$rate Hz · 每 ${intervalMs.toStringAsFixed(intervalMs == intervalMs.roundToDouble() ? 0 : 1)} ms 读取一次',
            ),
            Slider(
              key: const ValueKey('hid-read-rate'),
              value: AppSettings.hidReadRates.indexOf(rate).toDouble(),
              min: 0,
              max: (AppSettings.hidReadRates.length - 1).toDouble(),
              divisions: AppSettings.hidReadRates.length - 1,
              label: '$rate Hz',
              semanticFormatterCallback: (value) =>
                  '${AppSettings.hidReadRates[value.round()]} Hz',
              onChanged: (value) => unawaited(
                settings.setHidReadRateHz(
                  AppSettings.hidReadRates[value.round()],
                ),
              ),
            ),
            const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [Text('1 Hz'), Text('10 Hz')],
            ),
          ],
        ),
      ),
    );
  }

  Widget _parserCard(BuildContext context) {
    final theme = Theme.of(context);
    final editable = model.canConfigure;
    return Card.filled(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              editable
                  ? '修改后立即应用于后续采集与导入。'
                  : '请等待操作完成、断开设备并新建空会话后修改，以保持会话解析一致。',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            DropdownButtonFormField<DecodeProfile>(
              key: ValueKey(model.profile),
              initialValue: model.profile,
              isExpanded: true,
              decoration: const InputDecoration(labelText: '解析模式'),
              items: const [
                DropdownMenuItem(
                  value: DecodeProfile.witrnCompat,
                  child: Text('WITRN 兼容（含私有 PPS 位宽）'),
                ),
                DropdownMenuItem(
                  value: DecodeProfile.standard,
                  child: Text('标准 USB PD 位宽'),
                ),
              ],
              onChanged: editable
                  ? (value) {
                      if (value != null) {
                        model.configure(
                          decodeProfile: value,
                          crc: model.verifyCrc,
                          layout: model.reportLayout,
                        );
                      }
                    }
                  : null,
            ),
            const SizedBox(height: 20),
            DropdownButtonFormField<ReportLayout>(
              key: ValueKey(model.reportLayout),
              initialValue: model.reportLayout,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'HID 报告布局'),
              items: const [
                DropdownMenuItem(
                  value: ReportLayout.automatic,
                  child: Text('自动（依据报告边界与描述符）'),
                ),
                DropdownMenuItem(
                  value: ReportLayout.raw64,
                  child: Text('64 字节 WITRN 原始报告'),
                ),
                DropdownMenuItem(
                  value: ReportLayout.reportId65,
                  child: Text('65 字节（含额外 Report ID）'),
                ),
              ],
              onChanged: editable
                  ? (value) {
                      if (value != null) {
                        model.configure(
                          decodeProfile: model.profile,
                          crc: model.verifyCrc,
                          layout: value,
                        );
                      }
                    }
                  : null,
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('校验存在的 CRC'),
              subtitle: const Text('仅在报文末尾恰有 4 字节时校验；失败报文保留原文。'),
              value: model.verifyCrc,
              onChanged: editable
                  ? (value) => model.configure(
                      decodeProfile: model.profile,
                      crc: value,
                      layout: model.reportLayout,
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _shortcutsCard() => Card.filled(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Text(
        !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS
            ? '⌘ ,  设置\n⌘ N  新建采集会话\n⌘ O / ⌘ S  导入 / 导出图表\n⇧ ⌘ O / ⇧ ⌘ S  导入 / 导出报文\n⌘ R  刷新设备\n⌘ K  连接并自动采集\nF5  连接 / 继续采集\nShift + F5  断开 / 取消连接\n⌘ Return  暂停 / 继续采集\n⌘ L  切换跟随最新数据\n⌃ ⌘ F  切换全屏幕'
            : 'F5  连接 / 继续采集\nShift + F5  断开\nCtrl / ⌘ + O / S  导入 / 导出图表\nCtrl / ⌘ + Shift + O / S  导入 / 导出报文',
        style: const TextStyle(height: 2),
      ),
    ),
  );

  Widget _sectionTitle(BuildContext context, String title, IconData icon) =>
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
        child: Row(
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 12),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
      );
}
