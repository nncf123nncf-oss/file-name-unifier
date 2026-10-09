import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/exporter.dart';
import 'core/rename_engine.dart';

/// 画面の状態。保存するのはルール設定だけ（ファイル名・ファイルの中身は保存しない）。
class AppState extends ChangeNotifier {
  AppState({SharedPreferences? prefs}) : _prefs = prefs {
    final saved = RuleConfig.fromJsonString(prefs?.getString(_prefsKey));
    if (saved != null) rule = saved;
  }

  static const _prefsKey = 'rule_v1';

  final SharedPreferences? _prefs;

  RuleConfig rule = RuleConfig.initial;
  final List<FileInput> files = [];

  /// 選択時の上限などの知らせ。
  String? notice;

  bool exporting = false;
  int exportDone = 0;
  ExportResult? lastResult;

  List<PreviewRow> get preview => buildPreview(rule, files);

  int get totalBytes => files.fold(0, (sum, f) => sum + f.size);

  Future<void> pickFiles() async {
    final picked = await openFiles();
    if (picked.isEmpty) return;
    var added = 0;
    String? limit;
    for (final x in picked) {
      if (files.any((f) => f.path == x.path)) continue;
      final size = await x.length();
      limit = selectionLimitMessage(
        currentCount: files.length,
        currentBytes: totalBytes,
        addCount: 1,
        addBytes: size,
      );
      if (limit != null) break;
      files.add(
        FileInput(
          path: x.path,
          name: x.name,
          modified: await x.lastModified(),
          size: size,
        ),
      );
      added++;
    }
    notice = limit == null ? null : '$limit 追加できたのは$added件です。';
    lastResult = null;
    notifyListeners();
  }

  /// 起動時に渡されたファイル（exe のアイコンへのドロップなど）を、選んだ状態にする。
  /// 存在しないもの・フォルダ・`--` で始まる引数は読み飛ばす。上限は [pickFiles] と同じ。
  void addPaths(Iterable<String> paths) {
    var added = 0;
    String? limit;
    for (final path in paths) {
      if (path.startsWith('--')) continue;
      if (!FileSystemEntity.isFileSync(path)) continue;
      if (files.any((f) => f.path == path)) continue;
      final file = File(path);
      final size = file.lengthSync();
      limit = selectionLimitMessage(
        currentCount: files.length,
        currentBytes: totalBytes,
        addCount: 1,
        addBytes: size,
      );
      if (limit != null) break;
      files.add(
        FileInput(
          path: path,
          name: baseNameOf(path),
          modified: file.lastModifiedSync(),
          size: size,
        ),
      );
      added++;
    }
    notice = limit == null ? null : '$limit 追加できたのは$added件です。';
    lastResult = null;
    notifyListeners();
  }

  void clearFiles() {
    files.clear();
    notice = null;
    lastResult = null;
    notifyListeners();
  }

  void removeFile(FileInput file) {
    files.remove(file);
    notice = null;
    lastResult = null;
    notifyListeners();
  }

  /// 行ごとの取引先・書類種別・金額を直したとき。
  void touch() {
    lastResult = null;
    notifyListeners();
  }

  void setRule(RuleConfig next) {
    rule = next;
    lastResult = null;
    notifyListeners();
    _save();
  }

  void resetRule() => setRule(RuleConfig.initial);

  Future<void> _save() async {
    try {
      await _prefs?.setString(_prefsKey, rule.toJsonString());
    } catch (_) {
      // 保存できなくても動作に影響しない
    }
  }

  Future<void> export(String destDir) async {
    exporting = true;
    exportDone = 0;
    lastResult = null;
    notifyListeners();
    try {
      lastResult = await exportFiles(
        rule: rule,
        files: List.of(files),
        destDir: destDir,
        onProgress: (done, _) {
          exportDone = done;
          notifyListeners();
        },
      );
    } finally {
      exporting = false;
      notifyListeners();
    }
  }
}
