import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader/src/notes/note_scanner.dart';
import 'package:reader/src/ui/markdown_viewer.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 文内查找：打开查找条 → 输入 → 命中计数 → 上一处/下一处循环。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('find bar counts matches and cycles through them', (tester) async {
    final repo = Directory.systemTemp.createTempSync('reader-find-repo');
    addTearDown(() {
      if (repo.existsSync()) repo.deleteSync(recursive: true);
    });
    final file = File('${repo.path}${Platform.pathSeparator}note.md')
      ..writeAsStringSync(
        '# 第一章\n\n关键词 在这里\n\n## 第二章\n\n再来一个关键词\n',
      );
    final note = NoteFile(
      relativePath: 'note.md',
      absolutePath: file.path,
      modified: file.statSync().modified,
      sizeBytes: file.lengthSync(),
    );

    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: MarkdownViewerPage(note: note, repoRoot: repo.path),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 150));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // 打开查找条并输入
    await tester.tap(find.byIcon(Icons.search));
    await tester.pump();
    expect(find.text('在本文中查找'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '关键词');
    await tester.pump();
    expect(find.text('1/2'), findsOneWidget);
    // 当前命中所在行作为上下文预览显示
    expect(find.textContaining('关键词 在这里'), findsWidgets);
    // 正文渲染的文本节点里命中片段加了底色（逐字高亮）
    expect(_spansWithBackground(tester), greaterThan(0));

    await tester.tap(find.byTooltip('下一处'));
    await tester.pump();
    expect(find.text('2/2'), findsOneWidget);

    // 下一处再回到第一处（循环）
    await tester.tap(find.byTooltip('下一处'));
    await tester.pump();
    expect(find.text('1/2'), findsOneWidget);

    // 无匹配时给出明确提示
    await tester.enterText(find.byType(TextField).first, '不存在的词');
    await tester.pump();
    expect(find.text('无匹配'), findsOneWidget);

    // 关闭后查找条消失
    await tester.tap(find.byTooltip('关闭'));
    await tester.pump();
    expect(find.text('在本文中查找'), findsNothing);
  });

  testWidgets('opening from a search result pre-fills the find bar',
      (tester) async {
    final repo = Directory.systemTemp.createTempSync('reader-find-initial');
    addTearDown(() {
      if (repo.existsSync()) repo.deleteSync(recursive: true);
    });
    final file = File('${repo.path}${Platform.pathSeparator}note.md')
      ..writeAsStringSync(
        '# 一\n\n关键词 A\n\n## 二\n\n关键词 B\n\n关键词 C\n',
      );
    final note = NoteFile(
      relativePath: 'note.md',
      absolutePath: file.path,
      modified: file.statSync().modified,
      sizeBytes: file.lengthSync(),
    );

    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: MarkdownViewerPage(
            note: note,
            repoRoot: repo.path,
            initialFindQuery: '关键词',
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // 查找条已打开并统计出全部命中，首处已定位
    expect(find.text('1/3'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
  });
}

/// 统计渲染树里带背景色的 TextSpan 数量（查找命中底色高亮）。
int _spansWithBackground(WidgetTester tester) {
  var count = 0;
  void walk(InlineSpan? span) {
    if (span == null) return;
    if (span is TextSpan && span.style?.backgroundColor != null) count++;
    if (span is TextSpan) {
      span.children?.forEach(walk);
    }
  }

  tester.widgetList<RichText>(find.byType(RichText)).forEach((rich) {
    if (rich.text is TextSpan) walk(rich.text as TextSpan);
  });
  return count;
}
