import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader/src/git/repo_meta.dart';
import 'package:reader/src/git/sync_service.dart';
import 'package:reader/src/ui/updates_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 更新收件箱：跨仓库聚合 recentChanges，打开即清除，可全部已读。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  late Directory root;
  late Directory repoA;

  setUp(() {
    root = Directory.systemTemp.createTempSync('updates-repo');
    repoA = Directory('${root.path}${Platform.pathSeparator}a')..createSync();
    File('${repoA.path}${Platform.pathSeparator}note.md')
        .writeAsStringSync('# 笔记\n\n正文内容足够长，让阅读页能正常渲染。\n');
  });

  tearDown(() {
    // Windows 上后台扫描 isolate 可能还短暂持有句柄，清理失败不影响断言
    try {
      if (root.existsSync()) root.deleteSync(recursive: true);
    } on Object {
      // 忽略
    }
  });

  testWidgets('lists grouped changes and clears one on open', (tester) async {
    RepoMeta.setRecentChanges(repoA.path, const [
      RepoChange(path: 'note.md', added: true),
      RepoChange(path: 'sub/old.md', added: false),
    ]);

    await tester.pumpWidget(
      MaterialApp(
        home: UpdatesPage(
          sources: [(name: 'notes', root: repoA)],
        ),
      ),
    );
    await tester.pump();

    expect(find.text('更新收件箱'), findsOneWidget);
    expect(find.text('notes'), findsOneWidget);
    expect(find.text('note.md'), findsOneWidget);
    expect(find.text('old.md'), findsOneWidget);
    expect(find.text('新增'), findsOneWidget);
    expect(find.text('更新'), findsOneWidget);
    expect(find.text('sub'), findsOneWidget);

    await tester.tap(find.text('note.md'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // 打开阅读页后标记已清除
    expect(RepoMeta.readRecentChanges(repoA.path).containsKey('note.md'), false);

    // 返回收件箱：note.md 从列表消失，另一条还在
    Navigator.of(tester.element(find.byType(Scaffold).last)).pop();
    await tester.pumpAndSettle();
    expect(find.text('note.md'), findsNothing);
    expect(find.text('old.md'), findsOneWidget);
  });

  testWidgets('mark all read empties the inbox', (tester) async {
    RepoMeta.setRecentChanges(repoA.path, const [
      RepoChange(path: 'note.md', added: false),
    ]);

    await tester.pumpWidget(
      MaterialApp(
        home: UpdatesPage(
          sources: [(name: 'notes', root: repoA)],
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('全部已读'));
    await tester.pump();

    expect(find.text('没有未读的更新'), findsOneWidget);
    expect(RepoMeta.readRecentChanges(repoA.path), isEmpty);
  });
}
