import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader/src/git/repo_meta.dart';
import 'package:reader/src/notes/note_scanner.dart';
import 'package:reader/src/ui/markdown_viewer.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 续读：再次打开文章自动回到上次位置（不弹模态框），并保留「从头读」入口。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('reopen restores scroll position without a dialog',
      (tester) async {
    final repo = Directory.systemTemp.createTempSync('reader-resume');
    addTearDown(() {
      if (repo.existsSync()) repo.deleteSync(recursive: true);
    });
    final paragraphs =
        List.generate(80, (i) => '段落 $i：足够长的正文，撑出可滚动的长文。');
    final file = File('${repo.path}${Platform.pathSeparator}long.md')
      ..writeAsStringSync('# 标题\n\n${paragraphs.join('\n\n')}\n');
    // 上次读到一半（比例 + 标题索引 0）
    RepoMeta.saveProgressInfo(repo.path, 'long.md', 0.5, 0);

    final note = NoteFile(
      relativePath: 'long.md',
      absolutePath: file.path,
      modified: file.statSync().modified,
      sizeBytes: file.lengthSync(),
    );

    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(home: MarkdownViewerPage(note: note, repoRoot: repo.path)),
      );
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    // 首帧 + 恢复动画 + SnackBar 入场
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(AlertDialog), findsNothing, reason: '续读不再弹模态框');
    expect(find.textContaining('已回到上次位置'), findsOneWidget);
  });
}
