import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader/src/notes/note_scanner.dart';
import 'package:reader/src/ui/markdown_viewer.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 懒渲染（1.2）：长文只构建视口附近的块，但「跳到文末 / 目录跳转 /
/// 文内查找」仍要能到达视口外的内容。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('long body is built lazily but still reachable', (tester) async {
    final repo = Directory.systemTemp.createTempSync('reader-lazy-repo');
    addTearDown(() {
      if (repo.existsSync()) repo.deleteSync(recursive: true);
    });

    const sections = 40;
    final buffer = StringBuffer();
    for (var i = 1; i <= sections; i++) {
      buffer
        ..writeln('## 第 $i 节')
        ..writeln();
      for (var p = 1; p <= 6; p++) {
        buffer
          ..writeln('第 $i 节的第 $p 段正文，用来把文档撑到上百个块，'
              '验证懒渲染确实只构建视口附近的内容。')
          ..writeln();
      }
    }
    final file = File('${repo.path}${Platform.pathSeparator}long.md')
      ..writeAsStringSync('# 长文样本\n\n${buffer.toString()}');
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
    await tester.pump(const Duration(milliseconds: 100));

    // 首屏有内容；文末内容尚未构建（整篇一次性布局的时代这里会是 findsWidgets）
    expect(find.textContaining('第 1 节'), findsWidgets);
    expect(find.textContaining('第 $sections 节'), findsNothing);

    // 跳到文末：懒列表的 maxScrollExtent 是估算值，需要补齐才能到达真正末尾
    await tester.tap(find.byTooltip('跳到文末'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.textContaining('第 $sections 节'), findsWidgets,
        reason: '跳到文末应把最后一节构建出来');

    // 目录跳转：目标标题在视口外、尚未构建，走 scroll_to_index 的估算滚动
    await tester.tap(find.byTooltip('回到顶部'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.textContaining('第 6 节'), findsNothing,
        reason: '第 6 节在视口外，此时应尚未构建');
    await tester.tap(find.byTooltip('目录'));
    await tester.pumpAndSettle();
    expect(find.text('第 1 节'), findsWidgets, reason: '目录面板应已打开');
    await tester.tap(find.text('第 6 节'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.textContaining('第 6 节'), findsWidgets,
        reason: '目录跳转应落到第 6 节（跳转前该章节尚未构建）');
  });
}
