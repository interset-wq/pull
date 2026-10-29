import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader/src/local/local_folder_service.dart';
import 'package:reader/src/ui/markdown_editor.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 本地 Markdown 编辑器：保存写镜像、写回失败进入 pending、未保存离开提醒。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late File file;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    root = Directory.systemTemp.createTempSync('editor-test');
    file = File('${root.path}${Platform.pathSeparator}note.md')
      ..writeAsStringSync('# 原标题\n\n正文');
  });

  tearDown(() {
    try {
      if (root.existsSync()) root.deleteSync(recursive: true);
    } on Object {
      // Windows 句柄占用时忽略
    }
  });

  Future<void> pumpEditor(WidgetTester tester) async {
    final editor = MarkdownEditorPage(
      filePath: file.path,
      mirrorRoot: root.path,
      displayTitle: 'note',
      relativePath: 'note.md',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(builder: (_) => editor),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
  }

  testWidgets('save writes the mirror and records a pending write-back',
      (tester) async {
    await pumpEditor(tester);

    await tester.enterText(find.byType(TextField), '# 新标题\n\n改过的正文');
    // 保存会真实写文件：用 runAsync 等 IO 完成，pump 只推进动画
    await tester.runAsync(() async {
      await tester.tap(find.byTooltip('保存'));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(file.readAsStringSync(), contains('改过的正文'));
    // 没有授权文件夹记录时写回源侧必失败：镜像已保存，但必须记账，
    // 否则下次增量同步会用源侧旧内容覆盖镜像
    expect(LocalFolderService.pendingCount(root.path), 1);
    expect(find.textContaining('写回原文件夹失败'), findsOneWidget);
  });

  testWidgets('leaving with unsaved changes asks first', (tester) async {
    await pumpEditor(tester);
    await tester.enterText(find.byType(TextField), '未保存的改动');
    await tester.pump();

    final ctx = tester.element(find.byType(MarkdownEditorPage));
    await Navigator.of(ctx).maybePop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('未保存的修改'), findsOneWidget);

    await tester.tap(find.text('继续编辑'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(MarkdownEditorPage), findsOneWidget);
  });

  testWidgets('preview toggle swaps the source editor for rendered output',
      (tester) async {
    await pumpEditor(tester);
    expect(find.byType(TextField), findsOneWidget);

    await tester.tap(find.byTooltip('预览'));
    await tester.pump();
    expect(find.byType(TextField), findsNothing);
    expect(find.text('原标题'), findsWidgets);

    await tester.tap(find.byTooltip('编辑'));
    await tester.pump();
    expect(find.byType(TextField), findsOneWidget);
  });
}
