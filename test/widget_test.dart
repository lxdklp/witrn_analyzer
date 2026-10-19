import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:witrn_analyzer/app.dart';

void main() {
  testWidgets('app starts offline with CSV actions and no auto-open hardware', (
    tester,
  ) async {
    await tester.pumpWidget(const WitrnAnalyzerApp());
    expect(find.byTooltip('导入报文'), findsOneWidget);
    expect(find.byTooltip('导出报文'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.byTooltip('导入报文'),
      ),
      findsNothing,
    );
    await tester.tap(find.text('电参曲线'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('导入图表'), findsOneWidget);
    expect(find.byTooltip('导出图表'), findsOneWidget);
    expect(find.text('连接'), findsOneWidget);
    expect(find.text('开始'), findsNothing);
    expect(find.text('暂停'), findsOneWidget);
    expect(find.text('继续'), findsOneWidget);
    expect(
      tester
          .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '暂停'))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '继续'))
          .onPressed,
      isNull,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
