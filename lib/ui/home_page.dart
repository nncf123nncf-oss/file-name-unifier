import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../core/exporter.dart';
import '../core/rename_engine.dart';

String _formatBytes(int b) {
  if (b < 1024) return '$b B';
  if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
  return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
}

Future<void> _guard(
  BuildContext context,
  Future<void> Function() action,
) async {
  try {
    await action();
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('うまくいきませんでした: $e')));
    }
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ファイル名ととのえ'),
        actions: [
          TextButton(
            onPressed: () => _showAbout(context),
            child: const Text('このアプリについて'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListenableBuilder(
        listenable: state,
        builder: (context, _) => Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960),
            // 書き出し中は、ルールやファイルを触れないようにする（進捗が狂うため）
            child: AbsorbPointer(
              absorbing: state.exporting,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _FilesSection(state: state),
                  _RuleSection(state: state),
                  _RemoveSection(state: state),
                  _PreviewSection(state: state),
                  _ExportSection(state: state),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      '通信はしません。ログインも不要です。詳しくは右上の「このアプリについて」へ。',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

void _showAbout(BuildContext context) {
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('このアプリについて'),
      content: const SingleChildScrollView(
        child: SelectableText(
          'ファイル名ととのえ（バージョン 0.1.0・Windows）\n\n'
          'みちAIワークス（MICHI AI WORKS）／代表 田中　泉\n'
          '運営: みちAIワークス 公式サイト（https://michi-portfolio.vercel.app/ ）\n'
          'お問い合わせ: nncf123nncf@gmail.com\n\n'
          'このアプリは通信をしません。選んだファイルと名前は、お使いのパソコンの中だけで処理し、'
          'サーバーには送信しません。保存するのは、名前のルールの設定だけです。\n\n'
          '元のファイルは変更しません。新しい名前のコピーを、選んだ保存先に書き出します。'
          '保存先に同じ名前があるときは、上書きせずに連番を付けます。\n\n'
          'ログイン・会員登録・パスワードの入力を求めることはありません。',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('閉じる'),
        ),
      ],
    ),
  );
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// 入力欄。親の値が変わったとき（並べ替えなど）だけ中身を差し替える。
class _TextEntry extends StatefulWidget {
  const _TextEntry({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.width = 160,
  });

  final String label;
  final String value;
  final ValueChanged<String> onChanged;
  final double width;

  @override
  State<_TextEntry> createState() => _TextEntryState();
}

class _TextEntryState extends State<_TextEntry> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value,
  );

  @override
  void didUpdateWidget(_TextEntry oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != _controller.text) {
      _controller.value = TextEditingValue(
        text: widget.value,
        selection: TextSelection.collapsed(offset: widget.value.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      child: TextField(
        controller: _controller,
        onChanged: widget.onChanged,
        decoration: InputDecoration(
          labelText: widget.label,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}

// ───────────────────────── 1. ファイルを選ぶ ─────────────────────────

class _FilesSection extends StatelessWidget {
  const _FilesSection({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _SectionCard(
      title: '1. ファイルを選ぶ',
      children: [
        const Text('このアプリは通信しません。元のファイルは変更しません。'),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilledButton.icon(
              onPressed: () => _guard(context, state.pickFiles),
              icon: const Icon(Icons.upload_file),
              label: const Text('ファイルを選ぶ'),
            ),
            OutlinedButton(
              onPressed: state.files.isEmpty ? null : state.clearFiles,
              child: const Text('すべて外す'),
            ),
            Text(
              '${state.files.length}件 ／ 合計 ${_formatBytes(state.totalBytes)}（上限: $maxFileCount件・100MB）',
            ),
          ],
        ),
        if (state.notice != null) ...[
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, size: 18, color: scheme.error),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  state.notice!,
                  style: TextStyle(color: scheme.error),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

// ───────────────────────── 2. 名前のルール ─────────────────────────

class _RuleSection extends StatelessWidget {
  const _RuleSection({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final rule = state.rule;

    void moveBy(int index, int delta) {
      final parts = [...rule.parts];
      final item = parts.removeAt(index);
      parts.insert(index + delta, item);
      state.setRule(rule.copyWith(parts: parts));
    }

    void removeAt(int index) {
      final parts = [...rule.parts]..removeAt(index);
      state.setRule(rule.copyWith(parts: parts));
    }

    void setLiteral(int index, String text) {
      final parts = [...rule.parts];
      parts[index] = parts[index].withText(text);
      state.setRule(rule.copyWith(parts: parts));
    }

    return _SectionCard(
      title: '2. 名前のルール',
      children: [
        const Text('部品を並べて、新しい名前の形を決めます。矢印で順番を入れ替えられます。'),
        const SizedBox(height: 12),
        if (rule.parts.isEmpty)
          const Text('部品がありません。下から追加してください。')
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < rule.parts.length; i++)
                _PartCard(
                  key: ValueKey('part-$i'),
                  part: rule.parts[i],
                  canMoveBack: i > 0,
                  canMoveForward: i < rule.parts.length - 1,
                  onBack: () => moveBy(i, -1),
                  onForward: () => moveBy(i, 1),
                  onRemove: () => removeAt(i),
                  onLiteralChanged: (t) => setLiteral(i, t),
                ),
            ],
          ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text('部品を足す:'),
            for (final kind in PartKind.values)
              ActionChip(
                label: Text('＋ ${RulePart(kind).label}'),
                onPressed: kind != PartKind.literal && rule.usesPart(kind)
                    ? null
                    : () => state.setRule(
                        rule.copyWith(parts: [...rule.parts, RulePart(kind)]),
                      ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 24,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _LabeledDropdown<String>(
              label: '区切り',
              value: rule.separator,
              items: const {'_': '_（アンダーバー）', '-': '-（ハイフン）', '': 'なし'},
              onChanged: (v) => state.setRule(rule.copyWith(separator: v)),
            ),
            if (rule.usesPart(PartKind.date))
              _LabeledDropdown<DateStyle>(
                label: '日付の形',
                value: rule.dateStyle,
                items: const {
                  DateStyle.compact: '20261009',
                  DateStyle.hyphen: '2026-10-09',
                },
                onChanged: (v) => state.setRule(rule.copyWith(dateStyle: v)),
              ),
            if (rule.usesPart(PartKind.sequence))
              _LabeledDropdown<int>(
                label: '連番の桁数',
                value: rule.seqDigits,
                items: const {
                  1: '1桁（1）',
                  2: '2桁（01）',
                  3: '3桁（001）',
                  4: '4桁（0001）',
                },
                onChanged: (v) => state.setRule(rule.copyWith(seqDigits: v)),
              ),
          ],
        ),
        const SizedBox(height: 16),
        SelectableText(
          rule.describe(),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: rule.parts.isEmpty
                  ? null
                  : () async {
                      await Clipboard.setData(
                        ClipboardData(text: rule.describe()),
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('ルールの説明文をコピーしました')),
                        );
                      }
                    },
              icon: const Icon(Icons.copy, size: 18),
              label: const Text('ルールの説明文をコピー'),
            ),
            TextButton(
              onPressed: state.resetRule,
              child: const Text('ルールを初期値に戻す'),
            ),
          ],
        ),
      ],
    );
  }
}

class _PartCard extends StatelessWidget {
  const _PartCard({
    super.key,
    required this.part,
    required this.canMoveBack,
    required this.canMoveForward,
    required this.onBack,
    required this.onForward,
    required this.onRemove,
    required this.onLiteralChanged,
  });

  final RulePart part;
  final bool canMoveBack;
  final bool canMoveForward;
  final VoidCallback onBack;
  final VoidCallback onForward;
  final VoidCallback onRemove;
  final ValueChanged<String> onLiteralChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: '前へ',
            visualDensity: VisualDensity.compact,
            onPressed: canMoveBack ? onBack : null,
            icon: const Icon(Icons.chevron_left),
          ),
          if (part.kind == PartKind.literal)
            _TextEntry(
              label: '自由文字',
              value: part.text,
              onChanged: onLiteralChanged,
              width: 140,
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                '{${part.label}}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          IconButton(
            tooltip: '後ろへ',
            visualDensity: VisualDensity.compact,
            onPressed: canMoveForward ? onForward : null,
            icon: const Icon(Icons.chevron_right),
          ),
          IconButton(
            tooltip: 'この部品を外す',
            visualDensity: VisualDensity.compact,
            onPressed: onRemove,
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }
}

class _LabeledDropdown<T> extends StatelessWidget {
  const _LabeledDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String label;
  final T value;
  final Map<T, String> items;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$label: '),
        DropdownButton<T>(
          value: value,
          items: [
            for (final entry in items.entries)
              DropdownMenuItem<T>(value: entry.key, child: Text(entry.value)),
          ],
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ],
    );
  }
}

// ───────────────────────── 3. 取り除く文字 ─────────────────────────

class _RemoveSection extends StatefulWidget {
  const _RemoveSection({required this.state});

  final AppState state;

  @override
  State<_RemoveSection> createState() => _RemoveSectionState();
}

class _RemoveSectionState extends State<_RemoveSection> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _add() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    final rule = widget.state.rule;
    if (!rule.removeStrings.contains(text)) {
      widget.state.setRule(
        rule.copyWith(removeStrings: [...rule.removeStrings, text]),
      );
    }
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    final rule = widget.state.rule;
    return _SectionCard(
      title: '3. 取り除く文字',
      children: [
        const Text(
          'ここに登録した文字を、元の名前・取引先・書類種別から取り除きます。'
          '英字は大文字小文字を区別しません。単語の途中でも消えます（例: コピー用紙 → 用紙）。'
          '消したくない語は、チップの×で外してください。',
        ),
        const SizedBox(height: 12),
        if (rule.removeStrings.isEmpty)
          const Text('登録はありません（何も取り除きません）。')
        else
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final s in rule.removeStrings)
                InputChip(
                  label: Text(s),
                  onDeleted: () => widget.state.setRule(
                    rule.copyWith(
                      removeStrings: [...rule.removeStrings]..remove(s),
                    ),
                  ),
                ),
            ],
          ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 220,
              child: TextField(
                controller: _controller,
                onSubmitted: (_) => _add(),
                decoration: const InputDecoration(
                  labelText: '取り除く文字を足す',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            FilledButton.tonal(onPressed: _add, child: const Text('追加')),
            TextButton(
              onPressed: () => widget.state.setRule(
                rule.copyWith(removeStrings: defaultRemoveStrings),
              ),
              child: const Text('初期値に戻す'),
            ),
          ],
        ),
      ],
    );
  }
}

// ───────────────────────── 4. 変更前 → 変更後 ─────────────────────────

class _PreviewSection extends StatelessWidget {
  const _PreviewSection({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final rows = state.preview;
    final warnings = rows.where((r) => r.hasWarning).length;
    final scheme = Theme.of(context).colorScheme;
    return _SectionCard(
      title: '4. 変更前 → 変更後',
      children: [
        if (rows.isEmpty)
          const Text('ファイルを選ぶと、ここに変更前と変更後の名前が並びます。')
        else ...[
          Row(
            children: [
              Icon(
                warnings == 0
                    ? Icons.check_circle_outline
                    : Icons.warning_amber_rounded,
                size: 20,
                color: warnings == 0 ? scheme.primary : scheme.error,
              ),
              const SizedBox(width: 6),
              Text(
                warnings == 0
                    ? '${rows.length}件、問題ありません。'
                    : '${rows.length}件のうち$warnings件に注意があります。',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final row in rows)
            _PreviewTile(key: ValueKey(row.input.path), row: row, state: state),
        ],
      ],
    );
  }
}

class _PreviewTile extends StatelessWidget {
  const _PreviewTile({super.key, required this.row, required this.state});

  final PreviewRow row;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final rule = state.rule;
    final input = row.input;
    final (base, _) = splitName(input.name);
    final showRemoved =
        rule.usesPart(PartKind.original) && row.removedRanges.isNotEmpty;

    final before = _beforeText(
      context,
      base,
      showRemoved ? row.removedRanges : const [],
    );
    final after = SelectableText(
      row.newName,
      style: const TextStyle(fontWeight: FontWeight.bold),
    );

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(
          color: row.hasWarning ? scheme.error : scheme.outlineVariant,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth > 640;
              if (wide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: before),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Icon(Icons.arrow_forward),
                    ),
                    Expanded(child: after),
                    IconButton(
                      tooltip: 'この行を外す',
                      onPressed: () => state.removeFile(input),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  before,
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 4),
                    child: Icon(Icons.arrow_downward),
                  ),
                  after,
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => state.removeFile(input),
                      child: const Text('この行を外す'),
                    ),
                  ),
                ],
              );
            },
          ),
          if (showRemoved) ...[
            const SizedBox(height: 6),
            Text(
              '取り除いた文字: ${row.removedRanges.map((r) => base.substring(r.$1, r.$2)).join('、')}',
              style: TextStyle(color: scheme.error),
            ),
          ],
          if (row.dateUsed != null) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  '日付: ${formatDate(row.dateUsed!, DateStyle.hyphen)}'
                  '（${row.notes.contains(RowNote.dateFromName) ? '元の名前から読み取り' : 'ファイルの更新日'}）',
                ),
                // 元の名前に日付が読めた行だけ、どちらを使うか選べる（型番を日付と読んだときの回避）
                if (row.dateFoundInName == true)
                  TextButton(
                    onPressed: () {
                      input.preferModifiedDate = !input.preferModifiedDate;
                      state.touch();
                    },
                    child: Text(
                      input.preferModifiedDate ? '元の名前の日付を使う' : '更新日を使う',
                    ),
                  ),
              ],
            ),
          ],
          if (row.notes.any(
            (n) => n != RowNote.dateFromName && n != RowNote.dateFromModified,
          )) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final note in row.notes.where(
                  (n) =>
                      n != RowNote.dateFromName &&
                      n != RowNote.dateFromModified,
                ))
                  Chip(
                    visualDensity: VisualDensity.compact,
                    avatar: Icon(
                      note.isWarning
                          ? Icons.warning_amber_rounded
                          : Icons.info_outline,
                      size: 18,
                      color: note.isWarning ? scheme.error : null,
                    ),
                    label: Text(note.label),
                    backgroundColor: note.isWarning
                        ? scheme.errorContainer
                        : null,
                  ),
              ],
            ),
          ],
          if (rule.usesPart(PartKind.partner) ||
              rule.usesPart(PartKind.docType) ||
              rule.usesPart(PartKind.amount)) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (rule.usesPart(PartKind.partner))
                  _TextEntry(
                    key: ValueKey('${input.path}-partner'),
                    label: '取引先',
                    value: input.partner,
                    onChanged: (v) {
                      input.partner = v;
                      state.touch();
                    },
                  ),
                if (rule.usesPart(PartKind.docType))
                  _TextEntry(
                    key: ValueKey('${input.path}-docType'),
                    label: '書類種別',
                    value: input.docType,
                    onChanged: (v) {
                      input.docType = v;
                      state.touch();
                    },
                  ),
                if (rule.usesPart(PartKind.amount))
                  _TextEntry(
                    key: ValueKey('${input.path}-amount'),
                    label: '金額（数字）',
                    value: input.amount,
                    onChanged: (v) {
                      input.amount = v;
                      state.touch();
                    },
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _beforeText(
    BuildContext context,
    String base,
    List<(int, int)> removed,
  ) {
    final (_, ext) = splitName(row.input.name);
    final spans = <InlineSpan>[];
    var pos = 0;
    for (final (start, end) in removed) {
      if (start > pos) spans.add(TextSpan(text: base.substring(pos, start)));
      spans.add(
        TextSpan(
          text: base.substring(start, end),
          style: TextStyle(
            decoration: TextDecoration.lineThrough,
            color: Theme.of(context).colorScheme.error,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
      pos = end;
    }
    if (pos < base.length) spans.add(TextSpan(text: base.substring(pos)));
    spans.add(TextSpan(text: ext));
    return SelectableText.rich(TextSpan(children: spans));
  }
}

// ───────────────────────── 5. 書き出す ─────────────────────────

class _ExportSection extends StatelessWidget {
  const _ExportSection({required this.state});

  final AppState state;

  Future<void> _export(BuildContext context) async {
    final dir = await getDirectoryPath(confirmButtonText: 'ここに保存');
    if (dir == null) return;
    if (isSameFolder(state.files, dir) && context.mounted) {
      final go = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('元のファイルと同じフォルダです'),
          content: const Text(
            '選んだフォルダには、元のファイルがあります。ここに書き出すと、新しい名前のコピーが'
            '同じフォルダに増えます（元のファイルは変わりません）。続けますか？',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('やめる'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('続ける'),
            ),
          ],
        ),
      );
      if (go != true) return;
    }
    await state.export(dir);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final result = state.lastResult;
    return _SectionCard(
      title: '5. 書き出す',
      children: [
        const Text('新しい名前のコピーを、選んだフォルダに保存します。元のファイルは変更しません。'),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed:
              state.files.isEmpty || state.rule.parts.isEmpty || state.exporting
              ? null
              : () => _guard(context, () => _export(context)),
          icon: const Icon(Icons.save_alt),
          label: const Text('保存先を選んで書き出す'),
        ),
        if (state.exporting) ...[
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: state.files.isEmpty
                ? null
                : state.exportDone / state.files.length,
          ),
          const SizedBox(height: 4),
          Text('${state.exportDone} / ${state.files.length}件'),
        ],
        if (result != null) ...[
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  result.failCount == 0
                      ? '${result.okCount}件を書き出しました。元のファイルは変更していません。'
                      : '${result.okCount}件を書き出しました。${result.failCount}件は書き出せませんでした。元のファイルは変更していません。',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: result.failCount == 0 ? null : scheme.error,
                  ),
                ),
                const SizedBox(height: 4),
                SelectableText('保存先: ${result.destDir}'),
                if (result.numberedCount > 0)
                  Text('${result.numberedCount}件は保存先に同じ名前があったため、連番を付けました。'),
                if (result.sameFolder)
                  const Text('元のファイルと同じフォルダに保存しました。同じ名前になるものは連番になっています。'),
                if (result.failCount > 0) ...[
                  const SizedBox(height: 8),
                  Text(
                    '${result.failCount}件は書き出せませんでした:',
                    style: TextStyle(
                      color: scheme.error,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  for (final o in result.outcomes.where((o) => !o.ok))
                    SelectableText(
                      '・${o.originalName}（${o.error}）',
                      style: TextStyle(color: scheme.error),
                    ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}
