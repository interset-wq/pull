import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader/src/ui/code_viewer.dart';

/// 代码查看器：大纲跳转 / 文内查找 / 自动换行。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  late File file;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('code-viewer');
    final buffer = StringBuffer()
      ..writeln('class Alpha {}')
      ..writeln()
      ..writeln('// 占位注释')
      ..writeln()
      ..writeln('class Beta {');
    for (var i = 0; i < 30; i++) {
      buffer.writeln('  void method$i() {}');
    }
    buffer
      ..writeln('}')
      ..writeln()
      ..writeln('void tailFunction() {}');
    file = File('${temp.path}${Platform.pathSeparator}sample.dart')
      ..writeAsStringSync(buffer.toString());
  });

  tearDown(() {
    try {
      if (temp.existsSync()) temp.deleteSync(recursive: true);
    } on Object {
      // Windows 句柄占用时忽略
    }
  });

  Future<void> pumpPage(WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: CodeViewerPage(
            path: file.path,
            fileName: 'sample.dart',
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('outline jumps to a symbol near the end', (tester) async {
    await pumpPage(tester);

    await tester.tap(find.byTooltip('大纲'));
    await tester.pumpAndSettle();
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);

    // Beta 在第 5 行：跳过去后滚动位置应约等于 (5-1) × 行高
    await tester.tap(find.text('Beta'));
    await tester.pumpAndSettle();

    final scrollable = tester.state<ScrollableState>(
      find.byType(Scrollable).first,
    );
    final expected = 16.0 + 4 * 19.5;
    expect(scrollable.position.pixels, greaterThan(0),
        reason: '点大纲条目应滚到对应行');
    expect(scrollable.position.pixels, closeTo(expected, 40));
  });

  testWidgets('find bar counts and steps through matches', (tester) async {
    await pumpPage(tester);

    await tester.tap(find.byTooltip('查找'));
    await tester.pumpAndSettle();
    expect(find.text('在代码中查找'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'tailFunction');
    await tester.pump();
    expect(find.text('1/1'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '不存在的符号');
    await tester.pump();
    expect(find.text('无匹配'), findsOneWidget);

    await tester.tap(find.byTooltip('关闭'));
    await tester.pump();
    expect(find.text('在代码中查找'), findsNothing);
  });

  testWidgets('wrap toggle switches line wrapping mode', (tester) async {
    await pumpPage(tester);

    expect(find.byTooltip('自动换行'), findsOneWidget);
    await tester.tap(find.byTooltip('自动换行'));
    await tester.pump();
    expect(find.byTooltip('关闭自动换行'), findsOneWidget);

    await tester.tap(find.byTooltip('关闭自动换行'));
    await tester.pump();
    expect(find.byTooltip('自动换行'), findsOneWidget);
  });
}
