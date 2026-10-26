import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mermaid_flutter/mermaid_flutter.dart';

/// mermaid 接入冒烟测试：与阅读页相同包裹方式（FittedBox +
/// MaterialMermaidTheme.fromTheme）验证常见图类型可渲染、坏图走
/// errorBuilder 回退。不依赖真实仓库/文件。
void main() {
  Widget probe(String source,
      {Widget Function(BuildContext, Object)? errorBuilder}) {
    return MaterialApp(
      home: Builder(
        builder: (context) => FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.topLeft,
          child: MermaidDiagram(
            source: source,
            theme: MaterialMermaidTheme.fromTheme(Theme.of(context)),
            errorBuilder: errorBuilder,
          ),
        ),
      ),
    );
  }

  group('mermaid 图渲染（纯 Dart 原生）', () {
    testWidgets('flowchart 渲染出非零尺寸', (tester) async {
      await tester.pumpWidget(probe(
        'graph TD\n  A[开始] --> B{判断}\n  B -->|是| C[完成]\n  B -->|否| A',
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
      final size = tester.getSize(find.byType(MermaidDiagram));
      expect(size.width, greaterThan(0));
      expect(size.height, greaterThan(0));
    });

    testWidgets('sequence 渲染出非零尺寸', (tester) async {
      await tester.pumpWidget(probe(
        'sequenceDiagram\n  用户->>读者App: 打开文章\n  读者App-->>用户: 渲染完成',
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
      final size = tester.getSize(find.byType(MermaidDiagram));
      expect(size.width, greaterThan(0));
      expect(size.height, greaterThan(0));
    });

    testWidgets('gantt 渲染出非零尺寸', (tester) async {
      await tester.pumpWidget(probe(
        'gantt\n  title 计划\n  开发: 2026-10-01, 7d\n  测试: after 开发, 3d',
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
      final size = tester.getSize(find.byType(MermaidDiagram));
      expect(size.width, greaterThan(0));
      expect(size.height, greaterThan(0));
    });
  });

  group('坏图回退', () {
    testWidgets('解析失败触发 errorBuilder', (tester) async {
      var fallbackShown = false;
      await tester.pumpWidget(probe(
        'graph TD\n  A -->',
        errorBuilder: (context, error) {
          fallbackShown = true;
          return Text('图表解析失败：$error');
        },
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
      expect(fallbackShown, isTrue, reason: '坏图应走 errorBuilder 回退');
      expect(find.textContaining('图表解析失败'), findsOneWidget);
    });
  });
}
