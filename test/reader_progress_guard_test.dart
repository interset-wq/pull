import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader/src/git/repo_meta.dart';
import 'package:reader/src/notes/note_scanner.dart';
import 'package:reader/src/ui/markdown_viewer.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 续读恢复是程序化滚动：它触发的滚动事件不能被当成「用户读到的位置」
/// 保存，否则打开文章后立刻返回会把进度覆盖成动画中途的值。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('restore animation does not overwrite saved progress',
      (tester) async {
    final repo = Directory.systemTemp.createTempSync('reader-progress-guard');
    addTearDown(() {
      try {
        if (repo.existsSync()) repo.deleteSync(recursive: true);
      } on Object {
        // 忽略句柄占用
      }
    });
    final paragraphs =
        List.generate(120, (i) => '段落 $i：足够长的正文，撑出可滚动的长文。');
    final file = File('${repo.path}${Platform.pathSeparator}long.md')
      ..writeAsStringSync('# 标题\n\n${paragraphs.join('\n\n')}\n');
    // 读到 90%，没有标题锚点（走纯比例恢复，用 animateTo）
    RepoMeta.saveProgressInfo(repo.path, 'long.md', 0.9, null);

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
    await tester.pump();
    // 恢复动画（animateTo 300ms）期间逐帧检查：任何一帧都不能写进度
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      final (frame, _) = RepoMeta.readProgressInfo(repo.path, 'long.md');
      expect(frame, closeTo(0.9, 0.001),
          reason: '第 $i 帧把恢复动画的中途位置写成了阅读进度');
    }
    final (after, _) = RepoMeta.readProgressInfo(repo.path, 'long.md');
    expect(after, closeTo(0.9, 0.001));
  });
}
