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

  testWidgets('jump buttons are always visible', (tester) async {
    final repo = Directory.systemTemp.createTempSync('reader-jump-repo');
    final body = List.generate(60, (i) => '段落 $i：一些足够长的正文内容。').join('\n\n');
    final file = File('${repo.path}${Platform.pathSeparator}long.md')
      ..writeAsStringSync('# 标题\n\n$body\n');

    final note = NoteFile(
      relativePath: 'long.md',
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

    expect(find.byType(FloatingActionButton), findsNWidgets(3),
        reason: '目录 + 回顶/回底三个按钮应始终显示');

    await tester.drag(find.byType(Scrollable).first, const Offset(0, -800));
    await tester.pumpAndSettle();

    expect(find.byType(FloatingActionButton), findsNWidgets(3),
        reason: '滚动后按钮仍然显示');
  });
}
