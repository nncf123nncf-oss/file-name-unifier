import 'dart:io';

import 'package:file_name_unifier/core/exporter.dart';
import 'package:file_name_unifier/app_state.dart';
import 'package:file_name_unifier/core/rename_engine.dart';
import 'package:flutter_test/flutter_test.dart';

// 実際のファイルを使い、受け入れ基準 3（元ファイルが変わらない）と 4（上書きしない）を確かめる。
void main() {
  late Directory root;
  late Directory src;
  late Directory out;

  setUp(() {
    root = Directory.systemTemp.createTempSync('fnu_test_');
    src = Directory('${root.path}${Platform.pathSeparator}src')..createSync();
    out = Directory('${root.path}${Platform.pathSeparator}out')..createSync();
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  FileInput make(String name, List<int> bytes, {DateTime? modified}) {
    final f = File('${src.path}${Platform.pathSeparator}$name')
      ..writeAsBytesSync(bytes);
    if (modified != null) f.setLastModifiedSync(modified);
    return FileInput(
      path: f.path,
      name: name,
      modified: f.lastModifiedSync(),
      size: bytes.length,
    );
  }

  const original = RuleConfig(parts: [RulePart(PartKind.original)]);

  test('コピーが新しい名前で作られ、元ファイルの名前・更新日・中身は変わらない', () async {
    final a = make('請求書 (1).pdf', [
      1,
      2,
      3,
      4,
    ], modified: DateTime(2026, 1, 2, 3, 4, 5));
    final b = make(
      '写真.JPG',
      List.generate(1000, (i) => i % 256),
      modified: DateTime(2026, 5, 6),
    );
    final beforeA = (
      File(a.path).readAsBytesSync(),
      File(a.path).lastModifiedSync(),
    );
    final beforeB = (
      File(b.path).readAsBytesSync(),
      File(b.path).lastModifiedSync(),
    );

    final result = await exportFiles(
      rule: original,
      files: [a, b],
      destDir: out.path,
    );

    expect(result.okCount, 2);
    expect(result.failCount, 0);
    expect(
      File('${out.path}${Platform.pathSeparator}請求書.pdf').readAsBytesSync(),
      [1, 2, 3, 4],
    );
    expect(
      File('${out.path}${Platform.pathSeparator}写真.JPG').lengthSync(),
      1000,
    );

    // 元ファイル: 名前が残り、中身・更新日が同じ
    expect(File(a.path).existsSync(), isTrue);
    expect(File(a.path).readAsBytesSync(), beforeA.$1);
    expect(File(a.path).lastModifiedSync(), beforeA.$2);
    expect(File(b.path).readAsBytesSync(), beforeB.$1);
    expect(File(b.path).lastModifiedSync(), beforeB.$2);
    expect(src.listSync().length, 2);
  });

  test('保存先に同名があっても上書きせず、連番で保存される', () async {
    final a = make('請求書 (1).pdf', [9, 9, 9]);
    final existing = File('${out.path}${Platform.pathSeparator}請求書.pdf')
      ..writeAsBytesSync([7, 7]);

    final result = await exportFiles(
      rule: original,
      files: [a],
      destDir: out.path,
    );

    expect(existing.readAsBytesSync(), [7, 7], reason: '既存のファイルは変わらない');
    expect(
      File('${out.path}${Platform.pathSeparator}請求書_2.pdf').readAsBytesSync(),
      [9, 9, 9],
    );
    expect(result.outcomes.single.numbered, isTrue);
    expect(result.numberedCount, 1);
  });

  test('元のファイルと同じフォルダに保存しても上書きしない（同じ名前は連番）', () async {
    final a = make('資料.pdf', [1, 2]);
    final result = await exportFiles(
      rule: original,
      files: [a],
      destDir: src.path,
    );

    expect(result.sameFolder, isTrue);
    expect(File(a.path).readAsBytesSync(), [1, 2]);
    expect(
      File('${src.path}${Platform.pathSeparator}資料_2.pdf').readAsBytesSync(),
      [1, 2],
    );
  });

  test('元ファイルが消えている行は失敗として理由が返り、他の行は続けて書き出される', () async {
    final a = make('a.pdf', [1]);
    final b = make('b.pdf', [2]);
    File(a.path).deleteSync();

    final result = await exportFiles(
      rule: original,
      files: [a, b],
      destDir: out.path,
    );

    expect(result.okCount, 1);
    expect(result.failCount, 1);
    expect(result.outcomes.first.ok, isFalse);
    expect(result.outcomes.first.error, isNotEmpty);
    expect(
      File('${out.path}${Platform.pathSeparator}b.pdf').existsSync(),
      isTrue,
    );
  });

  test('進捗が件数ぶん通知される', () async {
    final files = [
      make('a.pdf', [1]),
      make('b.pdf', [2]),
      make('c.pdf', [3]),
    ];
    final seen = <int>[];
    await exportFiles(
      rule: original,
      files: files,
      destDir: out.path,
      onProgress: (done, total) => seen.add(done),
    );
    expect(seen, [1, 2, 3]);
  });

  test('日本語・記号を含む名前でも書き出せる', () async {
    final a = make('見積書　№1 ＆ 資料.xlsx', [5, 5, 5]);
    final result = await exportFiles(
      rule: original,
      files: [a],
      destDir: out.path,
    );
    expect(result.okCount, 1);
    expect(
      File('${out.path}${Platform.pathSeparator}見積書 №1 ＆ 資料.xlsx').existsSync(),
      isTrue,
    );
  });
  addPathsTests();
}

// 起動引数で渡されたファイルを選んだ状態にする（AppState.addPaths）。
void addPathsTests() {
  group('起動引数のファイル（addPaths）', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('fnu_args_'));
    tearDown(() => dir.deleteSync(recursive: true));

    String make(String name) {
      final f = File('${dir.path}${Platform.pathSeparator}$name')
        ..writeAsStringSync('x');
      return f.path;
    }

    test('ファイルだけが選ばれ、フォルダ・存在しないもの・--オプションは読み飛ばす', () {
      final state = AppState();
      state.addPaths([
        make('a.pdf'),
        make('b.pdf'),
        dir.path,
        '${dir.path}${Platform.pathSeparator}none.pdf',
        '--some-flag',
      ]);
      expect(state.files.map((f) => f.name), ['a.pdf', 'b.pdf']);
      expect(state.notice, isNull);
    });

    test('同じファイルは二重に入らず、51件目は理由つきで入らない', () {
      final state = AppState();
      final paths = [for (var i = 0; i < 52; i++) make('f$i.txt')];
      state.addPaths([paths.first, paths.first]); // 同じファイルは二重に入らない
      expect(state.files.length, 1);
      state.addPaths(paths);
      expect(state.files.length, 50);
      expect(state.notice, contains('50件まで'));
    });
  });
}
