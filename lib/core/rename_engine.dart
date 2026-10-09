// 名前の組み立て規則（画面・ファイル操作に依存しない純粋なロジック）。
// 仕様: work/100days/planning/day-064-requirements-file-renamer.md 第3節。
import 'dart:convert';

/// 選べるファイル数・合計サイズの上限（要件 M1）。
const int maxFileCount = 50;
const int maxTotalBytes = 100 * 1024 * 1024;

/// 拡張子を除いた名前がこの文字数を超えたら警告する（切り詰めはしない）。
const int longNameThreshold = 100;

const List<String> defaultRemoveStrings = [
  '(1)',
  '(2)',
  'コピー',
  '- Copy',
  '最終版',
];

enum PartKind { date, partner, docType, amount, sequence, original, literal }

class RulePart {
  const RulePart(this.kind, [this.text = '']);

  final PartKind kind;

  /// 自由文字（[PartKind.literal]）のときだけ使う。
  final String text;

  String get label => switch (kind) {
    PartKind.date => '日付',
    PartKind.partner => '取引先',
    PartKind.docType => '書類種別',
    PartKind.amount => '金額',
    PartKind.sequence => '連番',
    PartKind.original => '元の名前',
    PartKind.literal => text.isEmpty ? '自由文字' : text,
  };

  RulePart withText(String value) => RulePart(kind, value);

  Map<String, Object> toJson() => {
    'k': kind.name,
    if (kind == PartKind.literal) 't': text,
  };

  static RulePart? fromJson(Object? json) {
    if (json is! Map) return null;
    final name = json['k'];
    for (final kind in PartKind.values) {
      if (kind.name == name) {
        final text = json['t'];
        return RulePart(kind, text is String ? text : '');
      }
    }
    return null;
  }
}

enum DateStyle { compact, hyphen }

class RuleConfig {
  const RuleConfig({
    required this.parts,
    this.separator = '_',
    this.dateStyle = DateStyle.compact,
    this.seqDigits = 3,
    this.removeStrings = defaultRemoveStrings,
  });

  static const RuleConfig initial = RuleConfig(
    parts: [RulePart(PartKind.date), RulePart(PartKind.original)],
  );

  final List<RulePart> parts;
  final String separator;
  final DateStyle dateStyle;
  final int seqDigits;
  final List<String> removeStrings;

  RuleConfig copyWith({
    List<RulePart>? parts,
    String? separator,
    DateStyle? dateStyle,
    int? seqDigits,
    List<String>? removeStrings,
  }) => RuleConfig(
    parts: parts ?? this.parts,
    separator: separator ?? this.separator,
    dateStyle: dateStyle ?? this.dateStyle,
    seqDigits: seqDigits ?? this.seqDigits,
    removeStrings: removeStrings ?? this.removeStrings,
  );

  bool usesPart(PartKind kind) => parts.any((p) => p.kind == kind);

  /// 例: 「命名ルール: {日付}_{取引先}_{書類種別}」（要件 S2 のコピー用）
  String describe() {
    final names = parts.map(
      (p) => p.kind == PartKind.literal ? p.text : '{${p.label}}',
    );
    final dateNote = usesPart(PartKind.date)
        ? '（日付は${dateStyle == DateStyle.compact ? '20261009' : '2026-10-09'}の形）'
        : '';
    return '命名ルール: ${names.join(separator.isEmpty ? '' : separator)}$dateNote';
  }

  String toJsonString() => jsonEncode({
    'parts': [for (final p in parts) p.toJson()],
    'sep': separator,
    'date': dateStyle.name,
    'digits': seqDigits,
    'remove': removeStrings,
  });

  static RuleConfig? fromJsonString(String? source) {
    if (source == null) return null;
    try {
      final j = jsonDecode(source);
      if (j is! Map) return null;
      final parts = <RulePart>[
        for (final p in (j['parts'] as List? ?? const []))
          ?RulePart.fromJson(p),
      ];
      if (parts.isEmpty) return null;
      final sep = j['sep'];
      final digits = j['digits'];
      final remove = j['remove'];
      return RuleConfig(
        parts: parts,
        separator: sep is String && const ['_', '-', ''].contains(sep)
            ? sep
            : '_',
        dateStyle: DateStyle.values.firstWhere(
          (s) => s.name == j['date'],
          orElse: () => DateStyle.compact,
        ),
        seqDigits: digits is int && digits >= 1 && digits <= 6 ? digits : 3,
        removeStrings: remove is List
            ? [
                for (final r in remove)
                  if (r is String && r.isNotEmpty) r,
              ]
            : defaultRemoveStrings,
      );
    } catch (_) {
      return null;
    }
  }
}

/// 1ファイル分の入力。取引先・書類種別・金額は行ごとに編集できる。
class FileInput {
  FileInput({
    required this.path,
    required this.name,
    required this.modified,
    required this.size,
    String? amount,
  }) : amount = amount ?? amountFromName(name) ?? '';

  final String path;

  /// 拡張子つきの元の名前。
  final String name;
  final DateTime modified;
  final int size;
  String partner = '';
  String docType = '';
  String amount;

  /// 元の名前に日付があっても、ファイルの更新日を使う（型番や注文番号を日付と読んだときの回避用）。
  bool preferModifiedDate = false;
}

enum RowNote {
  invalidCharsReplaced('使えない文字を置換'),
  reservedName('Windowsの予約名のため末尾に_を追加'),
  tooLong('名前が長すぎます（100文字超）'),
  duplicateNumbered('同名のため連番を追加'),
  emptyFallback('全文字が消えるため元の名前のまま'),
  amountInvalid('金額の欄は数字だけにしてください（この行の金額は使いません）'),
  unchanged('変更なし'),
  dateFromName('日付: 元の名前から'),
  dateFromModified('日付: ファイルの更新日');

  const RowNote(this.label);
  final String label;

  /// 利用者に注意を促す種類か（情報だけのものは false）。
  bool get isWarning => switch (this) {
    invalidCharsReplaced ||
    reservedName ||
    tooLong ||
    duplicateNumbered ||
    emptyFallback ||
    amountInvalid => true,
    _ => false,
  };
}

class PreviewRow {
  PreviewRow({
    required this.input,
    required this.newName,
    required this.notes,
    required this.removedRanges,
    this.dateUsed,
    this.dateFoundInName,
    this.dateStripped = false,
  });

  final FileInput input;
  final String newName;
  final Set<RowNote> notes;

  /// 日付の部品に使った日付（日付の部品が無いときは null）。
  final DateTime? dateUsed;

  /// 元の名前に日付が読めたか（読めたが更新日を選んだ場合も true）。日付の部品が無いときは null。
  final bool? dateFoundInName;

  /// 元の名前から日付を取り除いたか（画面の「名前の中の日付は取り除きます」の表示に使う）。
  final bool dateStripped;

  /// 元の名前（拡張子を除いた部分）のうち、取り除かれた範囲 [start, end)。
  final List<(int, int)> removedRanges;

  bool get hasWarning => notes.any((n) => n.isWarning);
}

// ───────────────────────── 名前の部品 ─────────────────────────

/// 全角英数字・記号を半角へ（日付・金額の読み取り用。NFKC の代わり）。
String toHalfWidth(String s) {
  final buf = StringBuffer();
  for (final code in s.runes) {
    if (code >= 0xFF01 && code <= 0xFF5E) {
      buf.writeCharCode(code - 0xFEE0);
    } else if (code == 0x3000) {
      buf.write(' ');
    } else {
      buf.writeCharCode(code);
    }
  }
  return buf.toString();
}

DateTime? _validDate(int y, int m, int d) {
  final date = DateTime(y, m, d);
  return date.year == y && date.month == m && date.day == d ? date : null;
}

/// 元の名前から読んだ日付と、その文字の範囲 [start, end)（名前の先頭からの位置）。
typedef DateMatch = ({DateTime date, int start, int end});

/// 元の名前に含まれる日付を読む。`2026-09-05` `2026.9.5` `20260905` `2026年9月5日` `R8.9.5`。
/// 全角数字は半角に直して読む（全角→半角は1文字ずつの置き換えなので、範囲は元の名前と同じ位置）。
DateMatch? dateMatchInName(String name) {
  final s = toHalfWidth(name);
  final patterns = <RegExp>[
    RegExp(r'(?<!\d)(20\d{2})[-_.](\d{1,2})[-_.](\d{1,2})(?!\d)'),
    RegExp(r'(?<!\d)(20\d{2})\s?年\s?(\d{1,2})\s?月\s?(\d{1,2})\s?日'),
    RegExp(r'(?<!\d)(20\d{2})(\d{2})(\d{2})(?!\d)'),
  ];
  // 実在する日付として読めたものを全部集め、名前の中で一番前にあるものを使う
  // （名前に日付が複数あるとき、書式の種類ではなく位置で決める）
  final found = <DateMatch>[];
  for (final re in patterns) {
    for (final m in re.allMatches(s)) {
      final d = _validDate(
        int.parse(m[1]!),
        int.parse(m[2]!),
        int.parse(m[3]!),
      );
      if (d != null) found.add((date: d, start: m.start, end: m.end));
    }
  }
  // 令和（R1 = 2019）
  final reiwa = RegExp(
    r'(?<![A-Za-z])[Rr](\d{1,2})[.\-](\d{1,2})[.\-](\d{1,2})(?!\d)',
  );
  for (final m in reiwa.allMatches(s)) {
    final d = _validDate(
      2018 + int.parse(m[1]!),
      int.parse(m[2]!),
      int.parse(m[3]!),
    );
    if (d != null) found.add((date: d, start: m.start, end: m.end));
  }
  if (found.isEmpty) return null;
  found.sort(
    (a, b) => a.start != b.start
        ? a.start.compareTo(b.start)
        : b.end.compareTo(a.end),
  );
  return found.first;
}

/// 日付を囲む対応する括弧（`(2026-10-09)` `【2026-10-09】` など）まで、取り除く範囲に含める。
(int, int) _extendOverBrackets(String text, int start, int end) {
  const pairs = {
    '(': ')',
    '（': '）',
    '[': ']',
    '［': '］',
    '【': '】',
    '「': '」',
    '『': '』',
    '<': '>',
    '＜': '＞',
  };
  if (start > 0 && end < text.length && pairs[text[start - 1]] == text[end]) {
    return (start - 1, end + 1);
  }
  return (start, end);
}

DateTime? dateFromName(String name) => dateMatchInName(name)?.date;

String formatDate(DateTime d, DateStyle style) {
  String two(int n) => n.toString().padLeft(2, '0');
  final y = d.year.toString().padLeft(4, '0');
  return style == DateStyle.compact
      ? '$y${two(d.month)}${two(d.day)}'
      : '$y-${two(d.month)}-${two(d.day)}';
}

/// 元の名前から金額（円）を読む。`¥12,000` `12000円` のように印があるものだけ。無ければ null。
String? amountFromName(String name) {
  final s = toHalfWidth(name);
  // 数字の前後に数字・カンマが続くものは金額としない（1,2円 や ¥1,2345 の取り違えを防ぐ）。
  // 「円」の直後に文字が続くもの（3円グラフ・100円ショップ）も金額としない。
  final re = RegExp(
    r'(?:(?<![\d,])[¥￥]\s?(\d{1,3}(?:,\d{3})+|\d+)(?![\d,]))'
    r'|(?:(?<![\d,])(\d{1,3}(?:,\d{3})+|\d+)(?![\d,])\s?円(?![ぁ-んァ-ヶー一-龠a-zA-Z]))',
  );
  final m = re.firstMatch(s);
  if (m == null) return null;
  final digits = (m[1] ?? m[2])!.replaceAll(',', '');
  return digits.isEmpty ? null : digits;
}

/// 取り除く文字に一致した範囲 [start, end)。長い文字列を優先し、重なりは作らない。
List<(int, int)> findRemovedRanges(String text, List<String> removeStrings) {
  final targets = removeStrings.where((r) => r.isNotEmpty).toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  if (targets.isEmpty) return const [];
  final re = RegExp(targets.map(RegExp.escape).join('|'), caseSensitive: false);
  return [for (final m in re.allMatches(text)) (m.start, m.end)];
}

/// 範囲を、位置の順に並べて、重なる・隣り合うものを1つにまとめる。
List<(int, int)> _mergeRanges(List<(int, int)> ranges) {
  if (ranges.length < 2) return ranges;
  final sorted = [...ranges]..sort((a, b) => a.$1.compareTo(b.$1));
  final merged = <(int, int)>[sorted.first];
  for (final r in sorted.skip(1)) {
    final last = merged.last;
    if (r.$1 <= last.$2) {
      merged[merged.length - 1] = (last.$1, r.$2 > last.$2 ? r.$2 : last.$2);
    } else {
      merged.add(r);
    }
  }
  return merged;
}

const String _separatorChars = ' 　_-,，、';

bool _isSeparator(String ch) => _separatorChars.contains(ch);

String _trimLeadingSeparators(String s) {
  var i = 0;
  while (i < s.length && _isSeparator(s[i])) {
    i++;
  }
  return s.substring(i);
}

String _trimTrailingSeparators(String s) {
  var i = s.length;
  while (i > 0 && _isSeparator(s[i - 1])) {
    i--;
  }
  return s.substring(0, i);
}

/// [ranges]（位置順・重ならない）を取り除き、**取り除いた位置の前後だけ**を整える。
///
/// - 名前の先頭・末尾に来た取り除き跡の、前後の区切り（空白・`_`・`-`・`,`・`、`）を落とす
/// - 前と後ろの両方に区切りが残るときは、前の区切りだけを残す（`A_` + `_B` → `A_B`）
/// - 取り除いていない部分（`A--B` や先頭の `_` など）には触れない
/// - ドットは触らない（`.gitignore` のような名前を壊さない。末尾のドットは [_sanitize] が落とす）
String _removeAndTidy(String text, List<(int, int)> ranges) {
  if (ranges.isEmpty) return text;
  final segments = <String>[];
  var pos = 0;
  for (final (start, end) in ranges) {
    segments.add(text.substring(pos, start));
    pos = end;
  }
  segments.add(text.substring(pos));

  var result = segments.first;
  for (var i = 1; i < segments.length; i++) {
    final right = segments[i];
    final isLast = i == segments.length - 1;
    final leftTrimmed = _trimTrailingSeparators(result);
    if (leftTrimmed.isEmpty) {
      // 取り除き跡が名前の先頭に来る（前に区切りしか無い場合も含む）
      result = _trimLeadingSeparators(right);
    } else if (right.isEmpty && isLast) {
      // 取り除き跡が名前の末尾に来る
      result = leftTrimmed;
    } else {
      final rightTrimmed = _trimLeadingSeparators(right);
      final leftHasSeparator = leftTrimmed.length != result.length;
      final rightHasSeparator = rightTrimmed.length != right.length;
      result = leftHasSeparator && rightHasSeparator
          ? result + rightTrimmed
          : result + right;
    }
  }
  return result;
}

const Map<String, String> _invalidCharReplacement = {
  r'\': '＼',
  '/': '／',
  ':': '：',
  '*': '＊',
  '?': '？',
  '"': '＂',
  '<': '＜',
  '>': '＞',
  '|': '｜',
};

(String, bool) _sanitize(String s) {
  var changed = false;
  final buf = StringBuffer();
  for (final ch in s.split('')) {
    final rep = _invalidCharReplacement[ch];
    if (rep != null) {
      buf.write(rep);
      changed = true;
    } else if (ch.codeUnitAt(0) < 0x20) {
      changed = true; // 制御文字は捨てる
    } else {
      buf.write(ch);
    }
  }
  // Windows は末尾の空白・ドットを許さない
  final trimmed = buf.toString().replaceAll(RegExp(r'[ .]+$'), '');
  if (trimmed != buf.toString()) changed = true;
  return (trimmed, changed);
}

final RegExp _reserved = RegExp(
  r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$',
  caseSensitive: false,
);

(String, String) splitName(String name) {
  final i = name.lastIndexOf('.');
  if (i <= 0 || i == name.length - 1) return (name, '');
  return (name.substring(0, i), name.substring(i));
}

// ───────────────────────── プレビュー生成 ─────────────────────────

/// [existingNames] は保存先に既にあるファイル名（上書きを避けるため連番を振る）。
List<PreviewRow> buildPreview(
  RuleConfig config,
  List<FileInput> files, {
  Set<String> existingNames = const {},
}) {
  final taken = {for (final n in existingNames) n.toLowerCase()};
  final rows = <PreviewRow>[];
  for (var i = 0; i < files.length; i++) {
    rows.add(_buildRow(config, files[i], i + 1, taken));
  }
  return rows;
}

PreviewRow _buildRow(
  RuleConfig config,
  FileInput file,
  int seq,
  Set<String> taken,
) {
  final notes = <RowNote>{};
  final (origBase, ext) = splitName(file.name);

  // 日付の部品があるとき、元の名前から日付を読む。読み取った日付を使う行では、
  // 日付が二重にならないよう、元の名前の中のその日付を取り除く（更新日に切り替えた行は取り除かない）。
  final dateMatch = config.usesPart(PartKind.date)
      ? dateMatchInName(file.name)
      : null;
  final useNameDate = dateMatch != null && !file.preferModifiedDate;
  final stripDate =
      useNameDate &&
      config.usesPart(PartKind.original) &&
      dateMatch.end <= origBase.length;
  final removed = _mergeRanges([
    ...findRemovedRanges(origBase, config.removeStrings),
    // 日付を括弧で囲んでいる名前（`請求書(2026-10-09)`）は、括弧ごと取り除く
    if (stripDate)
      _extendOverBrackets(origBase, dateMatch.start, dateMatch.end),
  ]);

  // 取り除くものが無い欄は、そのまま使う（整形で名前を変えない）
  String cleaned(String raw) {
    final ranges = findRemovedRanges(raw, config.removeStrings);
    return ranges.isEmpty ? raw : _removeAndTidy(raw, ranges);
  }

  final values = <String>[];
  DateTime? dateUsed;
  bool? dateFound;
  for (final part in config.parts) {
    String value;
    switch (part.kind) {
      case PartKind.date:
        dateFound = dateMatch != null;
        dateUsed = useNameDate ? dateMatch.date : file.modified;
        value = formatDate(dateUsed, config.dateStyle);
        notes.add(
          useNameDate ? RowNote.dateFromName : RowNote.dateFromModified,
        );
      case PartKind.partner:
        value = cleaned(file.partner.trim());
      case PartKind.docType:
        value = cleaned(file.docType.trim());
      case PartKind.amount:
        // 数字（とカンマ・空白・¥・円）以外が混ざる入力は、別の数字に読み替えず使わない
        final stripped = toHalfWidth(file.amount)
            .trim()
            .replaceAll(RegExp(r'[,\s]'), '')
            .replaceAll(RegExp(r'^[¥￥]|円$'), '');
        if (stripped.isEmpty) {
          value = '';
        } else if (RegExp(r'^\d+$').hasMatch(stripped)) {
          value = '$stripped円';
        } else {
          value = '';
          notes.add(RowNote.amountInvalid);
        }
      case PartKind.sequence:
        value = seq.toString().padLeft(config.seqDigits, '0');
      case PartKind.original:
        value = removed.isEmpty ? origBase : _removeAndTidy(origBase, removed);
      case PartKind.literal:
        value = part.text.trim();
    }
    if (value.isNotEmpty) values.add(value);
  }

  var base = values.join(config.separator);
  var fellBack = false;
  if (base.isEmpty) {
    base = origBase;
    fellBack = true;
    notes.add(RowNote.emptyFallback);
  }

  final (safe, invalidChanged) = _sanitize(base);
  base = safe.isEmpty ? origBase : safe;
  if (invalidChanged && !fellBack) notes.add(RowNote.invalidCharsReplaced);

  // Windows は「最初のドットより前」が予約名かで判定する（CON.txt も CON.backup.txt も不可）
  final firstSegment = base.split('.').first.trimRight();
  if (_reserved.hasMatch(firstSegment)) {
    base = base.replaceFirst(firstSegment, '${firstSegment}_');
    notes.add(RowNote.reservedName);
  }
  if (base.length > longNameThreshold) notes.add(RowNote.tooLong);

  // 重複は後から来たものに連番を付ける（先に来たものはそのまま）
  var candidate = '$base$ext';
  var n = 1;
  while (taken.contains(candidate.toLowerCase())) {
    n++;
    candidate = '${base}_$n$ext';
    notes.add(RowNote.duplicateNumbered);
  }
  taken.add(candidate.toLowerCase());

  if (candidate == file.name) notes.add(RowNote.unchanged);

  return PreviewRow(
    input: file,
    newName: candidate,
    notes: notes,
    // 全文字が消えて元の名前に戻した行では、実際には消えていないので取り消し線を引かない
    removedRanges: fellBack ? const [] : removed,
    dateUsed: dateUsed,
    dateFoundInName: dateFound,
    dateStripped: stripDate && !fellBack,
  );
}

// ───────────────────────── 選択の上限 ─────────────────────────

/// 追加後の件数・合計サイズが上限を超える場合は、利用者向けの理由を返す。
String? selectionLimitMessage({
  required int currentCount,
  required int currentBytes,
  required int addCount,
  required int addBytes,
}) {
  if (currentCount + addCount > maxFileCount) {
    return 'ファイルは$maxFileCount件までです（いま$currentCount件、追加しようとしたのは$addCount件）。';
  }
  if (currentBytes + addBytes > maxTotalBytes) {
    return '合計サイズは100MBまでです。';
  }
  return null;
}
