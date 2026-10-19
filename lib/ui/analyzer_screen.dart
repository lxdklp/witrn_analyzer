import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../application/analyzer_view_model.dart';
import '../core/models.dart';
import '../data/chart_snapshot.dart';
import 'message_detail.dart';
import 'message_table.dart';
import 'power_chart.dart';
import 'telemetry_style.dart';
import 'session_actions.dart';

class AnalyzerScreen extends StatefulWidget {
  const AnalyzerScreen({super.key, required this.model});
  final AnalyzerViewModel model;
  @override
  State<AnalyzerScreen> createState() => _AnalyzerScreenState();
}

class _AnalyzerScreenState extends State<AnalyzerScreen> {
  final TextEditingController _search = TextEditingController();
  final PowerChartController _chartController = PowerChartController();
  late final AppLifecycleListener _lifecycle;
  AnalyzerViewModel get model => widget.model;
  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onExitRequested: () async {
        await model.shutdown();
        return AppExitResponse.exit;
      },
    );
  }

  @override
  void dispose() {
    _search.dispose();
    _chartController.dispose();
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _clear() => confirmNewSession(context, model);

  Future<void> _diagnostics() => showCaptureDiagnostics(context, model);

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.f5): () =>
          unawaited(model.connect()),
      const SingleActivator(LogicalKeyboardKey.f5, shift: true): () =>
          unawaited(model.disconnect()),
      const SingleActivator(LogicalKeyboardKey.keyO, control: true): () =>
          unawaited(model.importChart()),
      const SingleActivator(LogicalKeyboardKey.keyO, meta: true): () =>
          unawaited(model.importChart()),
      const SingleActivator(LogicalKeyboardKey.keyS, control: true): () =>
          unawaited(model.exportChart()),
      const SingleActivator(LogicalKeyboardKey.keyS, meta: true): () =>
          unawaited(model.exportChart()),
      const SingleActivator(
        LogicalKeyboardKey.keyO,
        control: true,
        shift: true,
      ): () =>
          unawaited(model.importCsv()),
      const SingleActivator(
        LogicalKeyboardKey.keyO,
        meta: true,
        shift: true,
      ): () =>
          unawaited(model.importCsv()),
      const SingleActivator(
        LogicalKeyboardKey.keyS,
        control: true,
        shift: true,
      ): () =>
          unawaited(model.exportCsv()),
      const SingleActivator(
        LogicalKeyboardKey.keyS,
        meta: true,
        shift: true,
      ): () =>
          unawaited(model.exportCsv()),
    },
    child: Focus(
      autofocus: true,
      child: ListenableBuilder(
        listenable: model,
        builder: (context, _) {
          final colors = Theme.of(context).colorScheme;
          return LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 1050;
              final mobile = constraints.maxWidth < 690;
              final controlsInBody = constraints.maxWidth < 960;
              final tabbed = mobile || constraints.maxHeight < 720;
              final tall = constraints.maxHeight > 780;
              return Scaffold(
                appBar: AppBar(
                  title: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!controlsInBody)
                        Padding(
                          padding: const EdgeInsets.only(right: 18),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(width: 6),
                              _selectedDevice(),
                              _controls(mobile),
                            ],
                          ),
                        ),
                      if (controlsInBody) _selectedDevice(),
                    ],
                  ),
                  actions: [
                    IconButton(
                      tooltip: '设置',
                      onPressed: () =>
                          Navigator.of(context).pushNamed('/settings'),
                      icon: const Icon(Icons.settings_outlined, size: 20),
                    ),
                    const SizedBox(width: 10),
                  ],
                ),
                body: SafeArea(
                  top: false,
                  child: Column(
                    children: [
                      if (model.busy)
                        const LinearProgressIndicator(minHeight: 2),
                      if (model.error case final error?)
                        Container(
                          width: double.infinity,
                          color: colors.errorContainer,
                          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                          child: Row(
                            children: [
                              Icon(
                                Icons.error_outline,
                                color: colors.onErrorContainer,
                                size: 18,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  error,
                                  style: TextStyle(
                                    color: colors.onErrorContainer,
                                    fontSize: 12,
                                  ),
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              IconButton(
                                tooltip: '关闭提示',
                                onPressed: model.clearError,
                                icon: const Icon(Icons.close, size: 16),
                              ),
                            ],
                          ),
                        ),
                      if (controlsInBody)
                        Padding(
                          padding: EdgeInsets.fromLTRB(
                            mobile ? 12 : 20,
                            10,
                            mobile ? 12 : 20,
                            12,
                          ),
                          child: _controls(mobile),
                        ),
                      if (mobile)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                          child: _telemetry(true),
                        ),
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: mobile ? 12 : 20,
                          ),
                          child: tabbed
                              ? DefaultTabController(
                                  length: 3,
                                  child: Column(
                                    children: [
                                      const TabBar(
                                        tabs: [
                                          Tab(text: '报文'),
                                          Tab(text: '电参曲线'),
                                          Tab(text: '源能力'),
                                        ],
                                      ),
                                      const SizedBox(height: 10),
                                      Expanded(
                                        child: TabBarView(
                                          children: [
                                            _messagePanel(false),
                                            if (mobile)
                                              _Panel(
                                                child: PowerChart(
                                                  model: model,
                                                  controller: _chartController,
                                                ),
                                              )
                                            else
                                              LayoutBuilder(
                                                builder: (context, size) =>
                                                    SingleChildScrollView(
                                                      child: Column(
                                                        children: [
                                                          _telemetry(mobile),
                                                          const SizedBox(
                                                            height: 10,
                                                          ),
                                                          SizedBox(
                                                            height:
                                                                (size.maxHeight -
                                                                        (mobile
                                                                            ? 190
                                                                            : 115))
                                                                    .clamp(
                                                                      320.0,
                                                                      double
                                                                          .infinity,
                                                                    ),
                                                            child: _Panel(
                                                              child: PowerChart(
                                                                model: model,
                                                                controller:
                                                                    _chartController,
                                                              ),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                              ),
                                            SingleChildScrollView(
                                              child: _capabilities(),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              : Column(
                                  children: [
                                    _telemetry(false),
                                    const SizedBox(height: 12),
                                    if (tall) ...[
                                      _capabilities(),
                                      const SizedBox(height: 12),
                                    ],
                                    Expanded(
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          Expanded(
                                            flex: 7,
                                            child: _messagePanel(wide),
                                          ),
                                          if (wide) ...[
                                            const SizedBox(width: 12),
                                            Expanded(
                                              flex: 4,
                                              child: _Panel(
                                                child: MessageDetail(
                                                  model: model,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    SizedBox(
                                      height: tall ? 280 : 240,
                                      child: _Panel(
                                        child: PowerChart(
                                          model: model,
                                          controller: _chartController,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: mobile ? 12 : 20,
                          vertical: 8,
                        ),
                        child: Row(
                          children: [
                            if (model.recording) ...[
                              Icon(
                                Icons.circle,
                                size: 7,
                                color: colors.primary,
                              ),
                              const SizedBox(width: 7),
                            ],
                            Expanded(
                              child: Text(
                                model.status,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                            ),
                            if (!mobile)
                              Text(
                                '接收 ${model.receivedReports}  ·  暂停忽略 ${model.pausedReports}  ·  丢弃 ${model.droppedReports}  ',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: colors.outline,
                                ),
                              ),
                            InkWell(
                              onTap: _diagnostics,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.info_outline,
                                      size: 13,
                                      color: model.diagnostics.isEmpty
                                          ? colors.outline
                                          : colors.tertiary,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      '${model.diagnostics.length}',
                                      style: const TextStyle(fontSize: 10),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    ),
  );

  Widget _selectedDevice() => SizedBox(
    width: 200,
    child: DropdownButtonFormField<String>(
      initialValue: model.selectedDevice?.path,
      key: ValueKey(model.selectedDevice?.path),
      isExpanded: true,
      decoration: const InputDecoration(
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        prefixIcon: Icon(Icons.usb, size: 17),
      ),
      hint: const Text('选择设备', style: TextStyle(fontSize: 12)),
      items: [
        for (final device in model.devices)
          DropdownMenuItem(
            value: device.path,
            child: Text(
              device.label,
              style: const TextStyle(fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: model.transitioning || model.connected
          ? null
          : (path) => model.selectDevice(
              model.devices.firstWhere((d) => d.path == path),
            ),
    ),
  );

  Widget _controls(bool mobile) => Wrap(
    spacing: 8,
    runSpacing: 8,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      IconButton(
        tooltip: '刷新设备',
        visualDensity: VisualDensity.compact,
        onPressed: model.scanning || model.transitioning || model.connected
            ? null
            : model.refreshDevices,
        icon: model.scanning
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.refresh, size: 20),
      ),
      OutlinedButton.icon(
        onPressed: model.busy || model.connection == ConnectionPhase.closing
            ? null
            : model.connected || model.connection == ConnectionPhase.connecting
            ? model.disconnect
            : model.connect,
        icon: Icon(model.connected ? Icons.link_off : Icons.link, size: 17),
        label: Text(
          model.connection == ConnectionPhase.connecting
              ? '取消连接'
              : model.connected
              ? '断开'
              : '连接',
        ),
      ),
      OutlinedButton.icon(
        onPressed: model.connected && model.recording && !model.busy
            ? model.pause
            : null,
        icon: const Icon(Icons.pause, size: 18),
        label: const Text('暂停'),
      ),
      FilledButton.icon(
        onPressed: model.connected && !model.recording && !model.busy
            ? model.start
            : null,
        icon: const Icon(Icons.play_arrow, size: 18),
        label: const Text('继续'),
      ),
      IconButton(
        tooltip: '新建会话',
        onPressed: model.busy || model.transitioning ? null : _clear,
        icon: const Icon(Icons.add_box_outlined, size: 19),
      ),
      if (!mobile) ...[
        if (model.source != ContentSource.live && model.fileName.isNotEmpty)
          Chip(
            visualDensity: VisualDensity.compact,
            label: Text(model.fileName, style: const TextStyle(fontSize: 11)),
            avatar: const Icon(Icons.description_outlined, size: 15),
          ),
      ],
    ],
  );

  Widget _messagePanel(bool wide) => _Panel(
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 8, 0),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'PD 报文',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                tooltip: '导入报文',
                onPressed: model.canImport ? model.importCsv : null,
                icon: const Icon(Icons.file_open_outlined, size: 20),
              ),
              IconButton(
                tooltip: '导出报文',
                onPressed: !model.busy && model.records.isNotEmpty
                    ? model.exportCsv
                    : null,
                icon: const Icon(Icons.save_alt, size: 20),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 36,
                  child: TextField(
                    controller: _search,
                    onChanged: (query) => model.setFilters(query: query),
                    decoration: const InputDecoration(
                      hintText: '搜索消息、序号、原始字节…',
                      prefixIcon: Icon(Icons.search, size: 18),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12),
                    ),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              PopupMenuButton<String>(
                tooltip: 'SOP 通道',
                icon: const Icon(Icons.filter_alt_outlined, size: 19),
                initialValue: model.sopFilter,
                itemBuilder: (_) => ['全部', ...PdMessage.sopNames.values]
                    .map(
                      (sop) => CheckedPopupMenuItem(
                        value: sop,
                        checked: model.sopFilter == sop,
                        child: Text(sop),
                      ),
                    )
                    .toList(),
                onSelected: (sop) => model.setFilters(sop: sop),
              ),
              IconButton(
                tooltip: model.hideGoodCrc ? '显示 GoodCRC' : '隐藏 GoodCRC',
                onPressed: () => model.setFilters(goodCrc: !model.hideGoodCrc),
                icon: Icon(
                  model.hideGoodCrc
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  size: 18,
                ),
              ),
              IconButton(
                tooltip: model.relativeTime ? '切换绝对时间' : '切换相对时间',
                onPressed: model.toggleRelative,
                icon: const Icon(Icons.schedule, size: 18),
              ),
            ],
          ),
        ),
        Expanded(
          child: MessageTable(
            model: model,
            onSelect: (record) {
              model.select(record);
              if (!wide) {
                Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (context) => Scaffold(
                      appBar: AppBar(title: const Text('报文详情')),
                      body: ListenableBuilder(
                        listenable: model,
                        builder: (_, _) => MessageDetail(model: model),
                      ),
                    ),
                  ),
                );
              }
            },
          ),
        ),
      ],
    ),
  );

  Widget _telemetry(bool mobile) {
    final t = model.latestTelemetry;
    final metrics = [
      ('VBUS', t?.voltage, 'V', TelemetryMetric.voltage.color),
      ('CURRENT', t?.current, 'A', TelemetryMetric.current.color),
      ('POWER', t?.power, 'W', TelemetryMetric.power.color),
      ('TEMPERATURE', t?.temperature, '°C', TelemetryMetric.temperature.color),
    ];
    if (mobile) {
      return _Panel(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          child: Column(
            children: [
              LayoutBuilder(
                builder: (context, constraints) => Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    for (final metric in metrics)
                      SizedBox(
                        width: (constraints.maxWidth - 8) / 2,
                        child: Row(
                          children: [
                            SizedBox(
                              width: 72,
                              child: Text(
                                metric.$1,
                                style: TextStyle(
                                  fontSize: 9,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                '${metric.$2?.toStringAsFixed(metric.$1 == 'TEMPERATURE' ? 1 : 3) ?? '—'} ${metric.$3}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: metric.$4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  for (final item in [
                    ('CC1', t?.cc1),
                    ('CC2', t?.cc2),
                    ('D+', t?.dp),
                    ('D−', t?.dn),
                  ])
                    Expanded(
                      child: Text(
                        '${item.$1} ${item.$2?.toStringAsFixed(1) ?? '—'} V',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 9,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      );
    }
    return Column(
      children: [
        LayoutBuilder(
          builder: (context, constraints) => Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final metric in metrics)
                SizedBox(
                  width:
                      (constraints.maxWidth - (mobile ? 10 : 30)) /
                      (mobile ? 2 : 4),
                  child: _Panel(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            metric.$1,
                            style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                              fontSize: 9,
                              letterSpacing: 1.3,
                            ),
                          ),
                          const SizedBox(height: 6),
                          RichText(
                            text: TextSpan(
                              children: [
                                TextSpan(
                                  text:
                                      metric.$2?.toStringAsFixed(
                                        metric.$1 == 'TEMPERATURE' ? 1 : 3,
                                      ) ??
                                      '—',
                                  style: TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: mobile ? 23 : 27,
                                    fontWeight: FontWeight.w600,
                                    color: metric.$4,
                                  ),
                                ),
                                TextSpan(
                                  text: '  ${metric.$3}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (final item in [
              ('CC1', t?.cc1),
              ('CC2', t?.cc2),
              ('D+', t?.dp),
              ('D−', t?.dn),
            ])
              Expanded(
                child: Text(
                  '${item.$1}  ${item.$2?.toStringAsFixed(2) ?? '—'} V',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 10,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _capabilities() => _Panel(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.bolt,
                size: 16,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 6),
              const Text(
                '源能力',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  model.latestRequest?.summary ??
                      '等待 Source Capabilities 与 Request',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          if (model.sourceCapabilities.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final pdo in model.sourceCapabilities)
                  Chip(
                    backgroundColor:
                        model.latestRequest?.position == pdo.position
                        ? Theme.of(context).colorScheme.secondaryContainer
                        : null,
                    label: Text(
                      '#${pdo.position}  ${pdo.summary}',
                      style: TextStyle(
                        color: model.latestRequest?.position == pdo.position
                            ? Theme.of(context).colorScheme.onSecondaryContainer
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 10,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    ),
  );
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Card.outlined(
    margin: EdgeInsets.zero,
    clipBehavior: Clip.antiAlias,
    child: child,
  );
}
