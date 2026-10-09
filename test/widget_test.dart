import 'package:file_name_unifier/app_state.dart';
import 'package:file_name_unifier/core/rename_engine.dart';
import 'package:file_name_unifier/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

FileInput file(String name) => FileInput(
  path: 'C:/in/$name',
  name: name,
  modified: DateTime(2026, 9, 5),
  size: 10,
);

Future<void> pumpAt(
  WidgetTester tester,
  AppState state, {
  double width = 1000,
  double height = 1600,
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(FileNameUnifierApp(state: state));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('初期表示: タイトルとルールの説明文が出る', (tester) async {
    await pumpAt(tester, AppState());
    expect(find.text('ファイル名ととのえ'), findsOneWidget);
    expect(find.textContaining('命名ルール: {日付}_{元の名前}'), findsOneWidget);
    expect(find.textContaining('元のファイルは変更しません'), findsWidgets);
  });

  testWidgets('部品を足すと、説明文に反映される', (tester) async {
    final state = AppState();
    await pumpAt(tester, state);
    await tester.tap(find.widgetWithText(ActionChip, '＋ 取引先'));
    await tester.pumpAndSettle();
    expect(state.rule.usesPart(PartKind.partner), isTrue);
    expect(find.textContaining('{取引先}'), findsWidgets);
  });

  testWidgets('取り除く文字のチップを外すと、変更後の名前に反映される', (tester) async {
    final state = AppState()
      ..files.add(file('請求書 (1).pdf'))
      ..setRule(const RuleConfig(parts: [RulePart(PartKind.original)]));
    await pumpAt(tester, state);
    expect(state.preview.single.newName, '請求書.pdf');

    await tester.tap(
      find.descendant(
        of: find.widgetWithText(InputChip, '(1)'),
        matching: find.byIcon(Icons.clear),
      ),
    );
    await tester.pumpAndSettle();
    expect(state.rule.removeStrings, isNot(contains('(1)')));
    expect(state.preview.single.newName, '請求書 (1).pdf');
  });

  testWidgets('全文字が消える行は注意として表示される', (tester) async {
    final state = AppState()
      ..files.add(file('(1).pdf'))
      ..setRule(const RuleConfig(parts: [RulePart(PartKind.original)]));
    await pumpAt(tester, state);
    expect(find.textContaining('全文字が消えるため元の名前のまま'), findsOneWidget);
    expect(find.textContaining('1件に注意があります'), findsOneWidget);
  });

  for (final width in [360.0, 800.0]) {
    testWidgets('幅${width.toInt()}pxで、はみ出しや例外が出ない', (tester) async {
      final state = AppState()
        ..files.addAll([
          file('請求書 (1).pdf'),
          file('見積書 - コピー.pdf'),
          file('IMG_001.jpg'),
        ])
        ..setRule(
          const RuleConfig(
            parts: [
              RulePart(PartKind.date),
              RulePart(PartKind.partner),
              RulePart(PartKind.docType),
              RulePart(PartKind.amount),
              RulePart(PartKind.literal, '社内'),
              RulePart(PartKind.sequence),
              RulePart(PartKind.original),
            ],
          ),
        );
      await pumpAt(tester, state, width: width, height: 2400);
      expect(tester.takeException(), isNull);
      expect(find.textContaining('3件'), findsWidgets);
    });
  }
}
