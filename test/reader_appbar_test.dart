import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader/src/notes/note_scanner.dart';
import 'package:reader/src/ui/markdown_viewer.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('reader shows app bar with back arrow, title and menu',
      (tester) async {
    final repo = Directory.systemTemp.createTempSync('reader-test-repo');
    final file = File('${repo.path}${Platform.pathSeparator}demo.md')
      ..writeAsStringSync('# Hello\n\nbody text\n\n## Sub\n\nmore\n');

    final note = NoteFile(
      relativePath: 'demo.md',
      absolutePath: file.path,
      modified: file.statSync().modified,
      sizeBytes: file.lengthSync(),
    );

    // 阅读页经由 push 进入（与真实流程一致，canPop 为 true 才显示返回箭头）
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => MarkdownViewerPage(
                        note: note,
                        repoRoot: repo.path,
                      ),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
    });
    await tester.tap(find.text('open'));
    await tester.pump();
    // 页面加载走真实文件 IO，需在 runAsync 中等待完成
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // 顶栏：返回箭头 + 标题 + 菜单
    expect(find.byIcon(Icons.arrow_back), findsOneWidget,
        reason: 'back arrow missing');
    expect(find.text('demo'), findsWidgets, reason: 'title missing');
    expect(find.byIcon(Icons.more_vert), findsOneWidget,
        reason: 'menu button missing');
  });
}
