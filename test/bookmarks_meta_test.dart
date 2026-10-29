import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader/src/git/repo_meta.dart';

/// 书签元数据：新增 / 去重 / 上限 / 删除。
void main() {
  late Directory root;
  late Directory repo;

  setUp(() {
    root = Directory.systemTemp.createTempSync('bookmarks-meta');
    repo = Directory('${root.path}${Platform.pathSeparator}notes')
      ..createSync();
  });

  tearDown(() {
    try {
      if (root.existsSync()) root.deleteSync(recursive: true);
    } on Object {
      // 忽略
    }
  });

  Bookmark bookmark(
    String path,
    double fraction, {
    String title = '章节',
    DateTime? at,
    int? heading,
  }) =>
      Bookmark(
        relativePath: path,
        fraction: fraction,
        title: title,
        headingIndex: heading,
        createdAt: at ?? DateTime.now(),
      );

  test('adds and lists newest first', () {
    final early = DateTime(2026, 10, 1, 9);
    final late = DateTime(2026, 10, 2, 9);
    RepoMeta.addBookmark(repo.path, bookmark('a.md', 0.2, at: early));
    RepoMeta.addBookmark(repo.path, bookmark('b.md', 0.6, at: late));

    final list = RepoMeta.readBookmarks(repo.path);
    expect(list, hasLength(2));
    expect(list.first.relativePath, 'b.md');
    expect(list.last.relativePath, 'a.md');
    expect(list.first.fraction, closeTo(0.6, 1e-9));
  });

  test('dedupes bookmarks within 1% on the same file', () {
    RepoMeta.addBookmark(repo.path, bookmark('a.md', 0.200));
    RepoMeta.addBookmark(repo.path, bookmark('a.md', 0.205, title: '新标题'));
    final list = RepoMeta.readBookmarks(repo.path);
    expect(list, hasLength(1));
    expect(list.single.title, '新标题');
  });

  test('keeps at most 100 bookmarks, dropping the oldest', () {
    for (var i = 0; i < 105; i++) {
      RepoMeta.addBookmark(
        repo.path,
        bookmark('a$i.md', 0.5, title: '第 $i 条',
            at: DateTime(2026, 1, 1).add(Duration(minutes: i))),
      );
    }
    final list = RepoMeta.readBookmarks(repo.path);
    expect(list, hasLength(100));
    expect(list.first.title, '第 104 条');
    expect(list.last.title, '第 5 条');
  });

  test('removes a single bookmark by path and creation time', () {
    final keep = bookmark('a.md', 0.1, at: DateTime(2026, 10, 1));
    final drop = bookmark('a.md', 0.5, at: DateTime(2026, 10, 2));
    RepoMeta.addBookmark(repo.path, keep);
    RepoMeta.addBookmark(repo.path, drop);

    RepoMeta.removeBookmark(repo.path, drop);
    final list = RepoMeta.readBookmarks(repo.path);
    expect(list, hasLength(1));
    expect(list.single.createdAt, keep.createdAt);
  });

  test('ignores corrupt entries', () {
    final file = File(
      '${root.path}${Platform.pathSeparator}.meta'
      '${Platform.pathSeparator}notes.json',
    )..createSync(recursive: true);
    file.writeAsStringSync(
      '{"bookmarks":[{"p":"a.md","f":0.3,"t":"好条目","ts":"2026-10-01T09:00:00"},'
      '{"p":42},{"f":"bad"}]}',
    );
    final list = RepoMeta.readBookmarks(repo.path);
    expect(list, hasLength(1));
    expect(list.single.relativePath, 'a.md');
  });
}
