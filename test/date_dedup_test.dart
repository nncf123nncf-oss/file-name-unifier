// 日付が二重にならないこと（読み取った日付は元の名前から取り除く）と、
// 取り除くものが無い名前は整形で変わらないことの確認。
import 'package:file_name_unifier/core/rename_engine.dart';
import 'package:flutter_test/flutter_test.dart';

FileInput f(String name, {DateTime? modified}) => FileInput(
  path: 'C:/in/$name',
  name: name,
  modified: modified ?? DateTime(2026, 3, 4),
  size: 10,
);

const dateAndOriginal = RuleConfig(
  parts: [RulePart(PartKind.date), RulePart(PartKind.original)],
);

String one(RuleConfig rule, FileInput file) =>
    buildPreview(rule, [file]).single.newName;

void main() {
  group('日付が二重にならない', () {
    test('名前の末尾の日付は、日付の部品に移り、元の名前からは消える', () {
      expect(one(dateAndOriginal, f('納品書_2026-10-09.pdf')), '20261009_納品書.pdf');
    });

    test('最終版などの取り除く文字と同時に取り除かれる', () {
      expect(
        one(dateAndOriginal, f('最終版_納品書_2026-10-09.pdf')),
        '20261009_納品書.pdf',
      );
    });

    test('名前の途中にある日付も取り除かれ、区切りが重ならない', () {
      expect(one(dateAndOriginal, f('A_2026-10-09_B.pdf')), '20261009_A_B.pdf');
      expect(
        one(dateAndOriginal, f('請求書2026年10月9日 見積.pdf')),
        '20261009_請求書 見積.pdf',
      );
    });

    test('全角数字・令和の日付も取り除かれる（範囲が元の名前と同じ位置）', () {
      expect(one(dateAndOriginal, f('請求書２０２６年１０月９日.pdf')), '20261009_請求書.pdf');
      expect(one(dateAndOriginal, f('メモR8.10.9.txt')), '20261009_メモ.txt');
    });

    test('名前が日付だけなら、日付の部品だけが残る（二重にならない）', () {
      expect(one(dateAndOriginal, f('20261009.pdf')), '20261009.pdf');
    });

    test('取り消し線の範囲に、日付の文字が含まれる', () {
      final row = buildPreview(dateAndOriginal, [
        f('納品書_2026-10-09.pdf'),
      ]).single;
      expect(row.removedRanges, [(4, 14)]);
      expect(row.dateUsed, DateTime(2026, 10, 9));
      expect(row.notes, contains(RowNote.dateFromName));
    });
  });

  group('読み違えた行は、更新日に切り替えると名前をそのまま残す', () {
    test('更新日を使う行では、元の名前の日付は消えない', () {
      final file = f('注文20250101.pdf')..preferModifiedDate = true;
      expect(one(dateAndOriginal, file), '20260304_注文20250101.pdf');
    });

    test('切り替えを戻すと、また取り除かれる', () {
      final file = f('注文20250101.pdf')..preferModifiedDate = true;
      file.preferModifiedDate = false;
      expect(one(dateAndOriginal, file), '20250101_注文.pdf');
    });

    test('切り替えても、他の取り除く文字は効く', () {
      final file = f('注文20250101 (1).pdf')..preferModifiedDate = true;
      expect(one(dateAndOriginal, file), '20260304_注文20250101.pdf');
    });
  });

  group('日付を取り除かない場面', () {
    test('日付の部品が無いルールでは、名前の日付は消えない', () {
      const rule = RuleConfig(parts: [RulePart(PartKind.original)]);
      expect(one(rule, f('納品書_2026-10-09.pdf')), '納品書_2026-10-09.pdf');
    });

    test('元の名前の部品が無いルールでは、何も取り除かない（行の名前に影響しない）', () {
      const rule = RuleConfig(
        parts: [RulePart(PartKind.date), RulePart(PartKind.literal, '書類')],
      );
      expect(one(rule, f('納品書_2026-10-09.pdf')), '20261009_書類.pdf');
    });

    test('名前に日付が無い行は、更新日が使われ、名前はそのまま', () {
      expect(one(dateAndOriginal, f('メモ.txt')), '20260304_メモ.txt');
    });
  });

  group('取り除くものが無い名前は、整形で変えない', () {
    const originalOnly = RuleConfig(parts: [RulePart(PartKind.original)]);

    test('連続する _ や全角スペースは、そのまま残る', () {
      expect(one(originalOnly, f('a__b.pdf')), 'a__b.pdf');
      expect(one(originalOnly, f('見積書　№1.pdf')), '見積書　№1.pdf');
      expect(one(originalOnly, f('名前_.pdf')), '名前_.pdf');
    });

    test('取り除いた名前だけが整形される（連続する区切りが1つに）', () {
      expect(one(originalOnly, f('A_コピー_B.pdf')), 'A_B.pdf');
    });

    test('取引先・書類種別も、取り除くものが無ければそのまま使う', () {
      const rule = RuleConfig(parts: [RulePart(PartKind.partner)]);
      final file = f('x.pdf')..partner = '山田__商店';
      expect(one(rule, file), '山田__商店.pdf');
    });
  });

  group('dateMatchInName', () {
    test('読んだ文字の範囲を返す', () {
      final m = dateMatchInName('請求書_2026-10-09_最終版.pdf')!;
      expect(m.date, DateTime(2026, 10, 9));
      expect('請求書_2026-10-09_最終版.pdf'.substring(m.start, m.end), '2026-10-09');
    });

    test('読めなければ null', () {
      expect(dateMatchInName('メモ.txt'), isNull);
      expect(dateMatchInName('メモ20260230.txt'), isNull);
    });
  });
}
