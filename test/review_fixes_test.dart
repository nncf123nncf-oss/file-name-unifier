// 公開前レビュー（minato-advocate）で指摘された不具合の再現と、修正の確認。
import 'dart:io';

import 'package:file_name_unifier/core/exporter.dart';
import 'package:file_name_unifier/core/rename_engine.dart';
import 'package:flutter_test/flutter_test.dart';

FileInput f(String name, {DateTime? modified}) => FileInput(
  path: 'C:/in/$name',
  name: name,
  modified: modified ?? DateTime(2026, 9, 5),
  size: 10,
);

void main() {
  group('予約名は「最初のドットより前」で判定する', () {
    PreviewRow row(String literal) => buildPreview(
      RuleConfig(parts: [RulePart(PartKind.literal, literal)]),
      [f('x.pdf')],
    ).single;

    test('COM1.x → COM1_.x.pdf', () {
      final r = row('COM1.x');
      expect(r.newName, 'COM1_.x.pdf');
      expect(r.notes, contains(RowNote.reservedName));
    });

    test('CON.backup → CON_.backup.pdf', () {
      expect(row('CON.backup').newName, 'CON_.backup.pdf');
    });

    test('CONSOLE や COM10 は予約名ではない', () {
      expect(row('CONSOLE').newName, 'CONSOLE.pdf');
      expect(row('COM10').newName, 'COM10.pdf');
    });
  });

  test('全文字が消えて元の名前に戻した行では、取り消し線（removedRanges）を返さない', () {
    final r = buildPreview(
      const RuleConfig(parts: [RulePart(PartKind.original)]),
      [f('(1) (2).pdf')],
    ).single;
    expect(r.newName, '(1) (2).pdf');
    expect(r.notes, contains(RowNote.emptyFallback));
    expect(r.removedRanges, isEmpty);
  });

  group('日付の誤判定は、行ごとに更新日へ切り替えられる', () {
    const rule = RuleConfig(parts: [RulePart(PartKind.date)]);

    test('型番・注文番号が日付と読まれた行は、何を採用したかが分かる', () {
      final r = buildPreview(rule, [f('注文20250101.pdf')]).single;
      expect(r.newName, '20250101.pdf');
      expect(r.dateUsed, DateTime(2025, 1, 1));
      expect(r.dateFoundInName, isTrue);
    });

    test('更新日を使うに切り替えると、更新日が使われる', () {
      final file = f('注文20250101.pdf', modified: DateTime(2026, 3, 4))
        ..preferModifiedDate = true;
      final r = buildPreview(rule, [file]).single;
      expect(r.newName, '20260304.pdf');
      expect(r.notes, contains(RowNote.dateFromModified));
      expect(r.dateFoundInName, isTrue, reason: '名前に日付が読めたこと自体は残る（戻すボタンを出すため）');
    });

    test('名前に日付が無い行は、切り替えボタンの対象外', () {
      final r = buildPreview(rule, [f('メモ.txt')]).single;
      expect(r.dateFoundInName, isFalse);
    });

    test('日付の部品が無いルールでは、日付の情報は null', () {
      final r = buildPreview(
        const RuleConfig(parts: [RulePart(PartKind.original)]),
        [f('a.pdf')],
      ).single;
      expect(r.dateUsed, isNull);
      expect(r.dateFoundInName, isNull);
    });
  });

  group('金額: 別の数字に読み替えない', () {
    test('自動で拾うのは、印があり、前後が正しいものだけ', () {
      expect(amountFromName('見積 ¥12,000.pdf'), '12000');
      expect(amountFromName('見積12000円_山田.pdf'), '12000');
      expect(amountFromName('見積 12,000円.pdf'), '12000');
      expect(amountFromName('3円グラフ.png'), isNull);
      expect(amountFromName('100円ショップ.pdf'), isNull);
      expect(amountFromName('1,2円.pdf'), isNull);
      expect(amountFromName('¥1,2345.pdf'), isNull);
      expect(amountFromName('20261009.pdf'), isNull);
    });

    RuleConfig amountRule() =>
        const RuleConfig(parts: [RulePart(PartKind.amount)]);

    test('入力欄に数字以外が混ざるときは使わず、注意を出す', () {
      for (final bad in ['1.5万', '-500', '約1000', 'abc']) {
        final file = f('a.pdf')..amount = bad;
        final r = buildPreview(
          const RuleConfig(
            parts: [
              RulePart(PartKind.literal, '請求'),
              RulePart(PartKind.amount),
            ],
          ),
          [file],
        ).single;
        expect(r.newName, '請求.pdf', reason: bad);
        expect(r.notes, contains(RowNote.amountInvalid), reason: bad);
        expect(r.hasWarning, isTrue);
      }
      expect(amountRule().parts.length, 1);
    });

    test('カンマ・円・¥・全角数字つきの正しい入力は使える', () {
      for (final good in ['12,000', '12000円', '¥12000', '１２０００', ' 12 000 ']) {
        final file = f('a.pdf')..amount = good;
        final r = buildPreview(
          const RuleConfig(
            parts: [
              RulePart(PartKind.literal, '請求'),
              RulePart(PartKind.amount),
            ],
          ),
          [file],
        ).single;
        expect(r.newName, endsWith('円.pdf'), reason: good);
        expect(r.notes, isNot(contains(RowNote.amountInvalid)), reason: good);
      }
    });
  });

  group('書き出しは既存のファイルを上書きしない（排他的作成）', () {
    late Directory root, src, out;

    setUp(() {
      root = Directory.systemTemp.createTempSync('fnu_fix_');
      src = Directory('${root.path}${Platform.pathSeparator}src')..createSync();
      out = Directory('${root.path}${Platform.pathSeparator}out')..createSync();
    });
    tearDown(() => root.deleteSync(recursive: true));

    FileInput make(String name, List<int> bytes) {
      final file = File('${src.path}${Platform.pathSeparator}$name')
        ..writeAsBytesSync(bytes);
      return FileInput(
        path: file.path,
        name: name,
        modified: file.lastModifiedSync(),
        size: bytes.length,
      );
    }

    const rule = RuleConfig(parts: [RulePart(PartKind.original)]);

    test('書き出し中に同名ファイルが現れても、既存の中身は変わらず、その行だけ失敗になる', () async {
      final a = make('a.pdf', [1]);
      final b = make('b.pdf', [2]);
      final intruder = File('${out.path}${Platform.pathSeparator}b.pdf');

      final result = await exportFiles(
        rule: rule,
        files: [a, b],
        destDir: out.path,
        // 1件目が終わった直後（2件目の前）に、別のプログラムが同名ファイルを作った状況
        onProgress: (done, total) {
          if (done == 1) intruder.writeAsBytesSync([9, 9, 9]);
        },
      );

      expect(intruder.readAsBytesSync(), [9, 9, 9], reason: '他のファイルを上書きしない');
      expect(result.outcomes[0].ok, isTrue);
      expect(result.outcomes[1].ok, isFalse);
      expect(result.outcomes[1].error, contains('止めました'));
    });

    test('書き出しに失敗した行は、空のファイルを残さない', () async {
      final a = make('a.pdf', [1]);
      final b = make('b.pdf', [2]);
      File(a.path).deleteSync();

      final result = await exportFiles(
        rule: rule,
        files: [a, b],
        destDir: out.path,
      );

      expect(result.outcomes[0].ok, isFalse);
      expect(
        File('${out.path}${Platform.pathSeparator}a.pdf').existsSync(),
        isFalse,
      );
      expect(
        File('${out.path}${Platform.pathSeparator}b.pdf').existsSync(),
        isTrue,
      );
    });

    test('isSameFolder は大文字小文字・末尾の区切りの違いを吸収する', () {
      final a = make('a.pdf', [1]);
      expect(isSameFolder([a], src.path), isTrue);
      expect(isSameFolder([a], '${src.path}${Platform.pathSeparator}'), isTrue);
      expect(isSameFolder([a], src.path.toUpperCase()), isTrue);
      expect(isSameFolder([a], out.path), isFalse);
    });
  });
}
