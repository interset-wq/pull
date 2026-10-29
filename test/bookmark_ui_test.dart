import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader/src/git/repo_meta.dart';
import 'package:reader/src/notes/note_scanner.dart';
import 'package:reader/src/ui/bookmarks_page.dart';
import 'package:reader/src/ui/markdown_viewer.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 书签交互：阅读页加书签 → 书签面板 → 删除；跨仓库书签页列表与删除。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late Directory repo;
  late NoteFile note;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    root = Directory.systemTemp.createTempSync('bookmarks-ui');
    repo = Directory('${root.path}${Platform.pathSeparator}notes')..createSync();
    final paragraphs = List.generate(
      80,
      (i) => '段落 $i：足够长的正文，撑出可滚动的长文。',
    );
    final file = File('${repo.path}${Platform.pathSeparator}long.md')
      ..writeAsStringSync('# 第一章\n\n${paragraphs.join('\n\n')}\n');
    note = NoteFile(
      relativePath: 'long.md',
      absolutePath: file.path,
      modified: file.statSync().modified,
      sizeBytes: file.lengthSync(),
    );
  });

  tearDown(() {
    try {
      if (root.existsSync()) root.deleteSync(recursive: true);
    } on Object {
      // Windows 句柄占用时忽略
    }
  });

  testWidgets('add a bookmark from the reader menu and delete it', (tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(home: MarkdownViewerPage(note: note, repoRoot: repo.path)),
      );
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('在此处加书签'));
    await tester.pumpAndSettle();

    final saved = RepoMeta.readBookmarks(repo.path);
    expect(saved, hasLength(1));
    expect(saved.single.relativePath, 'long.md');
    expect(find.textContaining('已加书签'), findsOneWidget);

    // 再开菜单：条目数已更新，打开书签面板
    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('书签（1）'));
    await tester.pumpAndSettle();
    expect(find.textContaining('% ·'), findsOneWidget);

    await tester.tap(find.byTooltip('删除书签'));
    await tester.pumpAndSettle();
    expect(RepoMeta.readBookmarks(repo.path), isEmpty);
  });

  testWidgets('opening with initialFraction jumps into the document',
      (tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: MarkdownViewerPage(
            note: note,
            repoRoot: repo.path,
            initialFraction: 0.5,
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    final scrollable = tester.state<ScrollableState>(
      find.byType(Scrollable).first,
    );
    expect(scrollable.position.pixels, greaterThan(0),
        reason: '带 initialFraction 打开应跳到文档中部，而不是停在顶部');
  });

  testWidgets('bookmarks page lists groups and deletes a row', (tester) async {
    RepoMeta.addBookmark(
      repo.path,
      Bookmark(
        relativePath: 'long.md',
        fraction: 0.4,
        title: '第一章',
        createdAt: DateTime(2026, 10, 1, 9),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: BookmarksPage(
          sources: [BookmarkSource(name: 'notes', root: repo)],
        ),
      ),
    );
    await tester.pump();

    expect(find.text('书签（1）'), findsOneWidget);
    expect(find.text('第一章'), findsOneWidget);
    expect(find.textContaining('long.md · 40%'), findsOneWidget);

    await tester.tap(find.byTooltip('删除书签'));
    await tester.pumpAndSettle();
    expect(find.text('还没有书签'), findsOneWidget);
    expect(RepoMeta.readBookmarks(repo.path), isEmpty);
  });
}
