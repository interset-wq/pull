import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader/src/search/repo_search.dart';

void main() {
  late Directory root;

  setUp(() {
    root = Directory(
      'temp/repo-search-${DateTime.now().microsecondsSinceEpoch}',
    )..createSync(recursive: true);
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  File write(String name, String content) {
    final file = File('${root.path}${Platform.pathSeparator}$name');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
    return file;
  }

  test('只搜正文文件，按命中次数排序', () {
    write('a.md', 'Flutter 阅读器\n再提一次 Flutter');
    write('b.md', 'Flutter');
    write('c.md', '无关内容');
    write('d.dart', 'Flutter');
    write('sub/e.txt', 'flutter 在子目录');

    final results = RepoSearchService.searchSync(
      repoRoot: root.path,
      query: 'FLUTTER',
    );

    expect(results.map((r) => r.relativePath), ['a.md', 'b.md', 'sub/e.txt']);
    expect(results.first.matches, 2);
    expect(results.first.snippets.first.line, 0);
  });

  test('点开头文件默认不进检索（与目录树一致）', () {
    write('.hidden.md', 'Flutter');
    write('visible.md', 'Flutter');

    final results = RepoSearchService.searchSync(
      repoRoot: root.path,
      query: 'Flutter',
    );
    expect(results.map((r) => r.relativePath), ['visible.md']);
  });

  test('复用调用方传入的文件列表（不重复扫描）', () {
    write('notes.md', '命中关键字');
    final results = RepoSearchService.searchSync(
      repoRoot: root.path,
      query: '关键字',
      files: const [],
    );
    expect(results, isEmpty, reason: '空列表意味着调用方已经筛过');
  });

  test('超大文件跳过（不拖慢一次检索）', () {
    final big = File('${root.path}${Platform.pathSeparator}big.txt');
    // 2MB + 1：超过 maxFileBytes
    big.writeAsBytesSync(
      List<int>.filled(RepoSearchService.maxFileBytes + 1, 0x41),
    );
    final results = RepoSearchService.searchSync(
      repoRoot: root.path,
      query: 'AAA',
    );
    expect(results, isEmpty);
  });

  test('多词 AND：缺一个词就不返回', () {
    write('a.md', 'flutter 状态 两个词');
    write('b.md', '只有 flutter');
    final results = RepoSearchService.searchSync(
      repoRoot: root.path,
      query: 'flutter 状态',
    );
    expect(results.map((r) => r.relativePath), ['a.md']);
  });

  test('路径命中全部关键词的排前面', () {
    write('flutter-state.md', 'flutter state');
    write('notes.md', 'flutter state flutter state');
    final results = RepoSearchService.searchSync(
      repoRoot: root.path,
      query: 'flutter state',
    );
    expect(results.length, 2);
    expect(results.first.relativePath, 'flutter-state.md',
        reason: '标题同时命中两个词时优先，即使正文命中次数更少');
  });

  test('空查询直接返回空，不做 IO', () {
    write('a.md', '内容');
    expect(
      RepoSearchService.searchSync(repoRoot: root.path, query: '  '),
      isEmpty,
    );
  });
}
