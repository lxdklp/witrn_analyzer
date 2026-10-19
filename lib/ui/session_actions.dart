import 'package:flutter/material.dart';

import '../application/analyzer_view_model.dart';

Future<void> confirmNewSession(
  BuildContext context,
  AnalyzerViewModel model,
) async {
  if (model.records.isNotEmpty || model.samples.isNotEmpty) {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('新建采集会话？'),
        content: const Text('当前报文和曲线将被清空。需要保留时，请分别导出报文和图表。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('新建会话'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
  }
  await model.clearSession();
}

Future<void> showCaptureDiagnostics(
  BuildContext context,
  AnalyzerViewModel model,
) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    title: const Text('采集与导入诊断'),
    content: SizedBox(
      width: 560,
      height: 340,
      child: model.diagnostics.isEmpty
          ? const Center(child: Text('没有会话级诊断。报文诊断可在详情中查看。'))
          : ListView.builder(
              itemCount: model.diagnostics.length,
              itemBuilder: (_, i) => ListTile(
                dense: true,
                title: Text(model.diagnostics[i].code),
                subtitle: Text(model.diagnostics[i].message),
              ),
            ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('关闭'),
      ),
    ],
  ),
);
