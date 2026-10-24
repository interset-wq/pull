import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader/src/notes/note_scanner.dart';
import 'package:reader/src/ui/markdown_viewer.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 回归：C6 案例文件黑屏（代码块在无界宽度下崩溃）。
/// markdown_widget 将 builder 结果包进 WidgetSpan，嵌套语境以无界宽度
/// 预量尺寸；代码块组件必须对两种约束都安全。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('C6 案例文件正常渲染不崩溃', (tester) async {
    final file = File(
      r'C:\Users\d111k\Documents\repos\llm-universe\docs\C6'
      r'\案例1：个人知识库助手.md',
    );
    if (!file.existsSync()) {
      // 本机无该文件时用等价结构的合成内容验证：嵌套列表中的代码块
      final tmp = File(
        '${Directory.systemTemp.createTempSync('reader-c6').path}'
        '${Platform.pathSeparator}case.md',
      )..writeAsStringSync('''
# 案例

## 步骤

1. 先执行：

   ```python
   print("hello")
   print("world")
   ```

2. 再执行：

   ```python
   ${List.filled(40, "x = 1").join('\n')}
   ```

- 表格内嵌：

  | 列1 | 列2 |
  | --- | --- |
  | `code` | 值 |
''');
      await _pumpFile(tester, tmp);
    } else {
      await _pumpFile(tester, file);
    }

    // 多泵几帧让布局跑完，任何 RenderFlex 崩溃都会让测试失败
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpFile(WidgetTester tester, File file) async {
  final note = NoteFile(
    relativePath: file.uri.pathSegments.last,
    absolutePath: file.path,
    modified: file.statSync().modified,
    sizeBytes: file.lengthSync(),
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark(),
      home: MarkdownViewerPage(note: note, repoRoot: file.parent.path),
    ),
  );
  await tester.pump(const Duration(milliseconds: 200));
}
