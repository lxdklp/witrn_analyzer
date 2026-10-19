import 'package:flutter/material.dart';

import '../application/analyzer_view_model.dart';
import '../core/models.dart';

class MessageTable extends StatefulWidget {
  const MessageTable({super.key, required this.model, required this.onSelect});
  final AnalyzerViewModel model;
  final ValueChanged<CaptureRecord> onSelect;
  @override
  State<MessageTable> createState() => _MessageTableState();
}

class _MessageTableState extends State<MessageTable> {
  final ScrollController _scroll = ScrollController();
  int _lastCount = 0;
  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final model = widget.model;
    final records = model.visibleRecords;
    final colors = Theme.of(context).colorScheme;
    if (records.length != _lastCount && model.followLatest) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
        }
      });
    }
    _lastCount = records.length;
    return LayoutBuilder(
      builder: (context, constraints) {
        final detailed = constraints.maxWidth >= 650;
        final small = constraints.maxWidth < 430;
        Widget cell(String value, double width, {TextStyle? style}) => SizedBox(
          width: width,
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style:
                style ?? const TextStyle(fontSize: 11, fontFamily: 'monospace'),
          ),
        );
        Widget row(CaptureRecord? record, {bool selected = false}) {
          final message = record?.message;
          return Row(
            children: [
              cell(record == null ? '#' : '${record.id}', small ? 36 : 48),
              cell(
                record == null ? '时间' : model.timeLabel(record),
                small ? 88 : 110,
              ),
              if (!small) cell(record == null ? 'SOP' : message!.sop, 70),
              if (detailed) ...[
                cell(
                  record == null ? 'Rev' : message!.header?.revision ?? '—',
                  42,
                ),
                cell(record == null ? 'PPR' : message!.powerRole, 70),
                cell(record == null ? 'PDR' : message!.dataRole, 46),
              ],
              Expanded(
                child: Text(
                  record == null ? '消息类型' : message!.type,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight:
                        message?.isSourceCapabilities == true ||
                            message?.request != null
                        ? FontWeight.w600
                        : FontWeight.normal,
                    color: selected
                        ? colors.onSecondaryContainer
                        : message == null
                        ? colors.onSurfaceVariant
                        : message.diagnostics.any(
                            (d) => d.severity == Severity.error,
                          )
                        ? colors.error
                        : message.isSourceCapabilities
                        ? colors.primary
                        : message.request != null
                        ? colors.tertiary
                        : null,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (record != null &&
                  message!.diagnostics.any((d) => d.severity != Severity.info))
                Tooltip(
                  message: message.diagnostics.map((d) => d.message).join('\n'),
                  child: Icon(
                    Icons.info_outline,
                    size: 13,
                    color: colors.tertiary,
                  ),
                ),
            ],
          );
        }

        return Column(
          children: [
            Container(
              height: 37,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: colors.surfaceContainerHigh,
                border: Border(
                  bottom: BorderSide(color: colors.outlineVariant),
                ),
              ),
              child: row(null),
            ),
            Expanded(
              child: records.isEmpty
                  ? SingleChildScrollView(
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                model.records.isEmpty ? '等待 PD 报文' : '没有匹配的报文',
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                model.records.isEmpty
                                    ? '连接 WITRN K2 后自动开始记录'
                                    : '调整搜索条件或 GoodCRC 过滤',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: colors.onSurfaceVariant,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                  : Scrollbar(
                      controller: _scroll,
                      child: NotificationListener<ScrollUpdateNotification>(
                        onNotification: (event) {
                          if (event.dragDetails != null && model.followLatest) {
                            model.setFollow(false);
                          }
                          return false;
                        },
                        child: ListView.builder(
                          controller: _scroll,
                          itemCount: records.length,
                          itemExtent: 42,
                          itemBuilder: (context, index) {
                            final record = records[index];
                            final selected = model.selected?.id == record.id;
                            return Material(
                              color: selected
                                  ? colors.secondaryContainer
                                  : index.isEven
                                  ? Colors.transparent
                                  : colors.surfaceContainerLow,
                              child: InkWell(
                                onTap: () => widget.onSelect(record),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                  ),
                                  decoration: BoxDecoration(
                                    border: Border(
                                      left: BorderSide(
                                        color: selected
                                            ? colors.primary
                                            : Colors.transparent,
                                        width: 2,
                                      ),
                                    ),
                                  ),
                                  child: DefaultTextStyle.merge(
                                    style: TextStyle(
                                      color: selected
                                          ? colors.onSecondaryContainer
                                          : colors.onSurface,
                                    ),
                                    child: row(record, selected: selected),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              child: Row(
                children: [
                  Text(
                    '${records.length} 条可见 / ${model.records.length} 条记录',
                    style: TextStyle(
                      fontSize: 10,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(40, 24),
                    ),
                    onPressed: () => model.setFollow(!model.followLatest),
                    child: Text(
                      model.followLatest ? '自动跟随' : '跟随最新',
                      style: const TextStyle(fontSize: 10),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
