// 新しい名前のコピーを保存先へ書き出す。元のファイルは読むだけで、変更・移動・削除しない。
import 'dart:io';

import 'rename_engine.dart';

class ExportOutcome {
  const ExportOutcome({
    required this.originalName,
    required this.newName,
    required this.ok,
    this.error,
    this.numbered = false,
  });

  final String originalName;
  final String newName;
  final bool ok;
  final String? error;

  /// 保存先に同名があったため、連番が付いたか。
  final bool numbered;
}

class ExportResult {
  const ExportResult({
    required this.destDir,
    required this.outcomes,
    required this.sameFolder,
  });

  final String destDir;
  final List<ExportOutcome> outcomes;

  /// 保存先が、選んだファイルのどれかと同じフォルダだったか。
  final bool sameFolder;

  int get okCount => outcomes.where((o) => o.ok).length;
  int get failCount => outcomes.length - okCount;
  int get numberedCount => outcomes.where((o) => o.numbered).length;
}

String baseNameOf(String path) {
  final i = path.lastIndexOf(RegExp(r'[\\/]'));
  return i < 0 ? path : path.substring(i + 1);
}

String _dirOf(String path) {
  final i = path.lastIndexOf(RegExp(r'[\\/]'));
  return i < 0 ? '' : path.substring(0, i);
}

String _normalizeDir(String dir) {
  var d = dir.replaceAll('/', r'\');
  while (d.length > 3 && d.endsWith(r'\')) {
    d = d.substring(0, d.length - 1);
  }
  return d.toLowerCase();
}

String _join(String dir, String name) {
  final sep = Platform.pathSeparator;
  return dir.endsWith('/') || dir.endsWith(r'\')
      ? '$dir$name'
      : '$dir$sep$name';
}

/// 保存先が、選んだファイルのどれかと同じフォルダか（書き出し前の確認用）。
bool isSameFolder(List<FileInput> files, String destDir) {
  final key = _normalizeDir(destDir);
  return files.any((f) => _normalizeDir(_dirOf(f.path)) == key);
}

String _friendlyError(Object e) {
  if (e is PathExistsException) {
    return '書き出し中に同じ名前のファイルが現れたため、止めました（既存のファイルは変えていません）';
  }
  if (e is PathNotFoundException) return '元のファイルが見つかりません';
  if (e is FileSystemException) {
    final msg = e.osError?.message.trim();
    return msg == null || msg.isEmpty ? e.message : msg;
  }
  return e.toString();
}

Future<ExportResult> exportFiles({
  required RuleConfig rule,
  required List<FileInput> files,
  required String destDir,
  void Function(int done, int total)? onProgress,
}) async {
  final dir = Directory(destDir);
  final existing = <String>{};
  if (await dir.exists()) {
    await for (final entity in dir.list(followLinks: false)) {
      existing.add(baseNameOf(entity.path));
    }
  }

  // 保存先に既にある名前は避けて連番を付ける（上書きしない）
  final rows = buildPreview(rule, files, existingNames: existing);
  // 保存先を考えない並びと比べて、連番が増えた行を知らせる
  final plain = buildPreview(rule, files);

  final sameFolder = isSameFolder(files, destDir);

  final outcomes = <ExportOutcome>[];
  for (var i = 0; i < rows.length; i++) {
    final row = rows[i];
    final target = _join(destDir, row.newName);
    final numbered = row.newName != plain[i].newName;
    var createdByUs = false;
    try {
      final targetFile = File(target);
      // 先に空のファイルを排他的に作る。同名が既にあれば（一覧を作った後に現れた場合も）
      // ここで失敗し、既存のファイルには触れない。作れたものは自分のものなので、コピーで埋める。
      await targetFile.create(exclusive: true);
      createdByUs = true;
      final source = File(row.input.path);
      await source.copy(target);
      final copied = await targetFile.length();
      if (copied != await source.length()) {
        throw const FileSystemException('コピー後のサイズが元と一致しません');
      }
      outcomes.add(
        ExportOutcome(
          originalName: row.input.name,
          newName: row.newName,
          ok: true,
          numbered: numbered,
        ),
      );
    } catch (e) {
      if (createdByUs) {
        // 途中で失敗した自分のファイルだけを片付ける（元ファイルや既存の他のファイルは消さない）
        try {
          await File(target).delete();
        } catch (_) {}
      }
      outcomes.add(
        ExportOutcome(
          originalName: row.input.name,
          newName: row.newName,
          ok: false,
          error: _friendlyError(e),
          numbered: numbered,
        ),
      );
    }
    onProgress?.call(i + 1, rows.length);
  }
  return ExportResult(
    destDir: destDir,
    outcomes: outcomes,
    sameFolder: sameFolder,
  );
}
