import 'package:file_name_unifier/core/rename_engine.dart';
import 'package:flutter_test/flutter_test.dart';

FileInput f(String name, {DateTime? modified, int size = 10}) => FileInput(
  path: 'C:/in/$name',
  name: name,
  modified: modified ?? DateTime(2026, 9, 5),
  size: size,
);

List<String> names(
  RuleConfig c,
  List<FileInput> files, {
  Set<String> existing = const {},
}) => buildPreview(
  c,
  files,
  existingNames: existing,
).map((r) => r.newName).toList();

const originalOnly = RuleConfig(parts: [RulePart(PartKind.original)]);

void main() {
  group('受け入れ基準 1: 拡張子を保持して新しい名前になる', () {
    test('pdf / jpg / xlsx で拡張子が保たれる（大文字小文字もそのまま）', () {
      const rule = RuleConfig(
        parts: [RulePart(PartKind.date), RulePart(PartKind.original)],
      );
      expect(names(rule, [f('見積.pdf'), f('写真.JPG'), f('表.xlsx')]), [
        '20260905_見積.pdf',
        '20260905_写真.JPG',
        '20260905_表.xlsx',
      ]);
    });

    test('拡張子のないファイル・先頭ドットのファイル', () {
      expect(names(originalOnly, [f('README'), f('.gitignore')]), [
        'README',
        '.gitignore',
      ]);
    });
  });

  group('受け入れ基準 2: 使えない文字・予約名・同名', () {
    test('使えない文字は全角に置換され、注意が付く', () {
      final rule = const RuleConfig(parts: [RulePart(PartKind.partner)]);
      final file = f('a.pdf')..partner = 'A/B:C*D?';
      final row = buildPreview(rule, [file]).single;
      expect(row.newName, 'A／B：C＊D？.pdf');
      expect(row.notes, contains(RowNote.invalidCharsReplaced));
    });

    test('Windows の予約名は末尾に _ が付く', () {
      const rule = RuleConfig(parts: [RulePart(PartKind.literal, 'CON')]);
      final row = buildPreview(rule, [f('x.pdf')]).single;
      expect(row.newName, 'CON_.pdf');
      expect(row.notes, contains(RowNote.reservedName));
    });

    test('末尾のドット・空白は落とす', () {
      const rule = RuleConfig(parts: [RulePart(PartKind.literal, '資料.')]);
      expect(names(rule, [f('x.pdf')]), ['資料.pdf']);
    });

    test('同名になる2件目以降に連番が付く', () {
      const rule = RuleConfig(parts: [RulePart(PartKind.literal, '資料')]);
      final rows = buildPreview(rule, [f('a.pdf'), f('b.pdf'), f('c.pdf')]);
      expect(rows.map((r) => r.newName), ['資料.pdf', '資料_2.pdf', '資料_3.pdf']);
      expect(rows[0].notes, isNot(contains(RowNote.duplicateNumbered)));
      expect(rows[1].notes, contains(RowNote.duplicateNumbered));
    });

    test('保存先に同名があれば上書きせず連番になる', () {
      const rule = RuleConfig(parts: [RulePart(PartKind.literal, '資料')]);
      expect(names(rule, [f('a.pdf')], existing: {'資料.pdf'}), ['資料_2.pdf']);
    });

    test('長い名前は切らずに警告だけ出す', () {
      final long = 'あ' * 101;
      final rule = RuleConfig(parts: [RulePart(PartKind.literal, long)]);
      final row = buildPreview(rule, [f('x.pdf')]).single;
      expect(row.newName, '$long.pdf');
      expect(row.notes, contains(RowNote.tooLong));
    });
  });

  group('受け入れ基準 2-2: 取り除く文字', () {
    test('請求書 (1).pdf → 請求書.pdf', () {
      expect(names(originalOnly, [f('請求書 (1).pdf')]), ['請求書.pdf']);
    });

    test('見積書 - コピー.pdf から「- コピー」が消える', () {
      expect(names(originalOnly, [f('見積書 - コピー.pdf')]), ['見積書.pdf']);
    });

    test('取り除いた結果が同名になる2件は連番で回避される', () {
      expect(names(originalOnly, [f('請求書 (1).pdf'), f('請求書.pdf')]), [
        '請求書.pdf',
        '請求書_2.pdf',
      ]);
    });

    test('全文字が消える名前は元の名前のまま残り、問題行になる', () {
      final row = buildPreview(originalOnly, [f('(1).pdf')]).single;
      expect(row.newName, '(1).pdf');
      expect(row.notes, contains(RowNote.emptyFallback));
      expect(row.hasWarning, isTrue);
    });

    test('消えた範囲が返る（取り消し線の表示用）', () {
      final row = buildPreview(originalOnly, [f('請求書 (1).pdf')]).single;
      expect(row.removedRanges, [(4, 7)]);
    });

    test('英字は大文字小文字を区別せず、長い文字列が優先される', () {
      expect(names(originalOnly, [f('Report - copy.txt')]), ['Report.txt']);
    });

    test('利用者が足した文字も取り除かれる', () {
      final rule = originalOnly.copyWith(
        removeStrings: [...defaultRemoveStrings, '本当の'],
      );
      expect(names(rule, [f('本当の請求書.pdf')]), ['請求書.pdf']);
    });

    test('取り除くリストが空なら何も消えない', () {
      final rule = originalOnly.copyWith(removeStrings: const []);
      expect(names(rule, [f('請求書 (1).pdf')]), ['請求書 (1).pdf']);
    });
  });

  group('受け入れ基準 2-3: 旅行_001.jpg', () {
    test('IMG_001 / IMG_002 → 旅行_001 / 旅行_002', () {
      const rule = RuleConfig(
        parts: [RulePart(PartKind.literal, '旅行'), RulePart(PartKind.sequence)],
      );
      expect(names(rule, [f('IMG_001.jpg'), f('IMG_002.jpg')]), [
        '旅行_001.jpg',
        '旅行_002.jpg',
      ]);
    });

    test('区切りなし・桁数変更', () {
      final rule = const RuleConfig(
        parts: [RulePart(PartKind.literal, '旅行'), RulePart(PartKind.sequence)],
      ).copyWith(separator: '', seqDigits: 2);
      expect(names(rule, [f('a.jpg'), f('b.jpg')]), ['旅行01.jpg', '旅行02.jpg']);
    });
  });

  group('日付', () {
    const rule = RuleConfig(parts: [RulePart(PartKind.date)]);

    test('元の名前の日付を使う（各書式）', () {
      expect(names(rule, [f('請求書_2026-10-09.pdf')]), ['20261009.pdf']);
      expect(names(rule, [f('請求書20261009.pdf')]), ['20261009.pdf']);
      expect(names(rule, [f('請求書2026年10月9日.pdf')]), ['20261009.pdf']);
      expect(names(rule, [f('請求書 2026.10.9.pdf')]), ['20261009.pdf']);
      expect(names(rule, [f('請求書R8.10.9.pdf')]), ['20261009.pdf']);
    });

    test('全角数字も読める', () {
      expect(names(rule, [f('請求書２０２６年１０月９日.pdf')]), ['20261009.pdf']);
    });

    test('日付が無ければ更新日を使い、どちらかが分かる', () {
      final row = buildPreview(rule, [
        f('メモ.txt', modified: DateTime(2026, 1, 2)),
      ]).single;
      expect(row.newName, '20260102.txt');
      expect(row.notes, contains(RowNote.dateFromModified));
      final row2 = buildPreview(rule, [f('メモ_20261009.txt')]).single;
      expect(row2.notes, contains(RowNote.dateFromName));
    });

    test('存在しない日付（2月30日）は日付として読まない', () {
      expect(
        names(rule, [f('メモ20260230.txt', modified: DateTime(2026, 3, 1))]),
        ['20260301.txt'],
      );
    });

    test('ハイフン書式', () {
      expect(names(rule.copyWith(dateStyle: DateStyle.hyphen), [f('a.pdf')]), [
        '2026-09-05.pdf',
      ]);
    });

    test('8桁の数字の一部は日付にしない（前後に数字が続く場合）', () {
      expect(dateFromName('12026100912.pdf'), isNull);
    });
  });

  group('金額', () {
    test('印（¥・円）があるものだけ読み、日付とは混同しない', () {
      expect(amountFromName('見積 ¥12,000.pdf'), '12000');
      expect(amountFromName('見積 12000円.pdf'), '12000');
      expect(amountFromName('見積20261009.pdf'), isNull);
    });

    test('金額欄が空なら部品ごと省略され、区切りが重ならない', () {
      const rule = RuleConfig(
        parts: [
          RulePart(PartKind.partner),
          RulePart(PartKind.amount),
          RulePart(PartKind.docType),
        ],
      );
      final file = f('a.pdf')
        ..partner = '山田商店'
        ..docType = '請求書';
      expect(buildPreview(rule, [file]).single.newName, '山田商店_請求書.pdf');
      file.amount = '12000';
      expect(buildPreview(rule, [file]).single.newName, '山田商店_12000円_請求書.pdf');
    });
  });

  group('選択の上限', () {
    test('51件目は理由つきで入らない', () {
      expect(
        selectionLimitMessage(
          currentCount: 50,
          currentBytes: 0,
          addCount: 1,
          addBytes: 1,
        ),
        contains('50件まで'),
      );
      expect(
        selectionLimitMessage(
          currentCount: 49,
          currentBytes: 0,
          addCount: 1,
          addBytes: 1,
        ),
        isNull,
      );
    });

    test('合計100MB超は入らない', () {
      expect(
        selectionLimitMessage(
          currentCount: 1,
          currentBytes: maxTotalBytes,
          addCount: 1,
          addBytes: 1,
        ),
        contains('100MB'),
      );
    });
  });

  group('ルールの保存と説明文', () {
    test('JSON を往復できる', () {
      final rule =
          const RuleConfig(
            parts: [
              RulePart(PartKind.date),
              RulePart(PartKind.literal, '社内'),
              RulePart(PartKind.sequence),
            ],
          ).copyWith(
            separator: '-',
            seqDigits: 4,
            dateStyle: DateStyle.hyphen,
            removeStrings: ['x'],
          );
      final back = RuleConfig.fromJsonString(rule.toJsonString())!;
      expect(back.parts.map((p) => p.label), ['日付', '社内', '連番']);
      expect(back.separator, '-');
      expect(back.seqDigits, 4);
      expect(back.dateStyle, DateStyle.hyphen);
      expect(back.removeStrings, ['x']);
    });

    test('壊れた保存値は null（初期値に戻せる）', () {
      expect(RuleConfig.fromJsonString('{bad'), isNull);
      expect(RuleConfig.fromJsonString(null), isNull);
      expect(RuleConfig.fromJsonString('{"parts":[]}'), isNull);
    });

    test('説明文', () {
      const rule = RuleConfig(
        parts: [
          RulePart(PartKind.date),
          RulePart(PartKind.partner),
          RulePart(PartKind.docType),
        ],
      );
      expect(rule.describe(), '命名ルール: {日付}_{取引先}_{書類種別}（日付は20261009の形）');
    });
  });
}
