import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader/src/notes/note_scanner.dart';
import 'package:reader/src/ui/markdown_viewer.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Notebook 富输出在阅读页真正出图 / 出表，而不是一行占位。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('notebook image and table outputs are rendered', (tester) async {
    final repo = Directory.systemTemp.createTempSync('reader-ipynb-repo');
    addTearDown(() {
      if (repo.existsSync()) repo.deleteSync(recursive: true);
    });

    // 1×1 透明 PNG
    const png =
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQ'
        'DwAEhQGAhKmMIQAAAABJRU5ErkJggg==';
    final nb = jsonEncode({
      'cells': [
        {
          'cell_type': 'markdown',
          'source': ['# Notebook 渲染'],
        },
        {
          'cell_type': 'code',
          'source': ['plt.plot()'],
          'outputs': [
            {
              'output_type': 'execute_result',
              'data': {
                'text/plain': ['<Figure size 640x480 with 1 Axes>'],
                'image/png': png,
              },
            },
          ],
        },
        {
          'cell_type': 'code',
          'source': ['df.head()'],
          'outputs': [
            {
              'output_type': 'execute_result',
              'data': {
                'text/html': [
                  '<table><thead><tr><th>name</th><th>count</th></tr></thead>',
                  '<tbody><tr><td>a</td><td>3</td></tr></tbody></table>',
                ],
                'text/plain': ['  name count\n0 a 3'],
              },
            },
          ],
        },
      ],
      'metadata': {
        'language_info': {'name': 'python'},
      },
      'nbformat': 4,
    });
    final file = File('${repo.path}${Platform.pathSeparator}note.ipynb')
      ..writeAsStringSync(nb);
    final note = NoteFile(
      relativePath: 'note.ipynb',
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

    // 图表出图（Image.memory），不是「暂不支持」占位；matplotlib 的
    // <Figure ...> 文本占位也不再出现
    expect(find.byType(Image), findsWidgets);
    expect(find.textContaining('暂不支持'), findsNothing);
    expect(find.textContaining('<Figure'), findsNothing);

    // pandas 表格降级成 Markdown 表格，表头可见
    expect(find.textContaining('name'), findsWidgets);
    expect(find.textContaining('count'), findsWidgets);
  });
}
