import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../application/analyzer_view_model.dart';
import '../core/models.dart';

class MessageDetail extends StatelessWidget {
  const MessageDetail({super.key, required this.model});
  final AnalyzerViewModel model;
  @override
  Widget build(BuildContext context) {
    final record = model.selected;
    final colors = Theme.of(context).colorScheme;
    if (record == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.account_tree_outlined,
                size: 38,
                color: colors.outline,
              ),
              const SizedBox(height: 14),
              const Text('选择一条报文'),
              const SizedBox(height: 6),
              Text(
                '查看字段、位域与原始字节',
                style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }
    final message = record.message;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 12, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '报文详情  /  #${record.id}',
                      style: TextStyle(
                        color: colors.onSurfaceVariant,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      message.type,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: '复制原始字节',
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: record.rawHex));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context)
                        .showSnackBar(const SnackBar(content: Text('已复制 Raw')));
                  }
                },
                icon: const Icon(Icons.copy_outlined, size: 18),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _Badge(message.sop),
                  _Badge('PD ${message.header?.revision ?? '—'}'),
                  _Badge('ID ${message.header?.messageId ?? '—'}'),
                  _Badge('CRC ${message.crcStatus.name}'),
                ],
              ),
              const SizedBox(height: 14),
              SelectableText(
                message.summary,
                style: TextStyle(fontSize: 13, color: colors.primary),
              ),
              for (final diagnostic in message.diagnostics)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: diagnostic.severity == Severity.error
                          ? colors.errorContainer
                          : colors.tertiaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${diagnostic.code}\n${diagnostic.message}',
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.5,
                        color: diagnostic.severity == Severity.error
                            ? colors.onErrorContainer
                            : colors.onTertiaryContainer,
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 14),
              for (final field in message.fields) _FieldTile(field: field),
              const SizedBox(height: 18),
              Text(
                'PD RAW  ·  ${message.raw.length} bytes',
                style: TextStyle(
                  color: colors.onSurfaceVariant,
                  fontSize: 10,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 8),
              _RawBytes(bytes: message.raw),
              const SizedBox(height: 16),
              Text(
                'WITRN REPORT  ·  ${record.report.length} bytes',
                style: TextStyle(
                  color: colors.onSurfaceVariant,
                  fontSize: 10,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 8),
              _RawBytes(bytes: record.report),
              const SizedBox(height: 12),
              Text(
                '解析模式：${model.profile.name}',
                style: TextStyle(fontSize: 10, color: colors.outline),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RawBytes extends StatelessWidget {
  const _RawBytes({required this.bytes});
  final List<int> bytes;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(8),
    ),
    child: SelectableText(
      bytes.map((v) => hexValue(v, 2).substring(2)).join(' '),
      style: const TextStyle(
        fontFamily: 'monospace',
        fontSize: 11,
        height: 1.8,
      ),
    ),
  );
}

class _Badge extends StatelessWidget {
  const _Badge(this.label);
  final String label;
  @override
  Widget build(BuildContext context) => Chip(label: Text(label));
}

class _FieldTile extends StatelessWidget {
  const _FieldTile({required this.field});
  final FieldNode field;
  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    if (field.children.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 6,
              child: Text(
                field.label,
                style: TextStyle(fontSize: 11, color: color.onSurfaceVariant),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 5,
              child: SelectableText(
                field.displayValue,
                style: const TextStyle(fontSize: 11),
              ),
            ),
            if (field.bitRange != null)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Text(
                  '[${field.bitRange}]',
                  style: TextStyle(fontSize: 9, color: color.outline),
                ),
              ),
          ],
        ),
      );
    }
    return ExpansionTile(
      key: PageStorageKey(field.label),
      initiallyExpanded: true,
      tilePadding: const EdgeInsets.symmetric(horizontal: 4),
      childrenPadding: const EdgeInsets.only(left: 8),
      dense: true,
      shape: const Border(),
      collapsedShape: const Border(),
      title: Text(
        field.label,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
      subtitle: field.raw == null
          ? null
          : Text(
              hexValue(field.raw!),
              style: TextStyle(
                fontSize: 10,
                color: color.primary,
                fontFamily: 'monospace',
              ),
            ),
      children: field.children
          .map((field) => _FieldTile(field: field))
          .toList(),
    );
  }
}
