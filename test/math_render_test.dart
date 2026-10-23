import 'package:flutter_test/flutter_test.dart';
import 'package:reader/src/notes/math_render.dart';
import 'package:markdown/markdown.dart' as m;

void main() {
  final doc = m.Document(
    inlineSyntaxes: [MathInlineSyntax(), MathBlockSyntax()],
  );

  group('数学公式语法解析', () {
    test('行内公式 \$...\$ 生成 math 节点', () {
      final nodes = doc.parseInline('质能方程 \$E=mc^2\$ 很有名');
      final tags =
          nodes.whereType<m.Element>().map((e) => e.tag).toList();
      expect(tags.contains('math'), isTrue);
    });

    test('单个美元金额 \$100 不误判为公式', () {
      final nodes = doc.parseInline('花了 \$100 买书');
      final tags =
          nodes.whereType<m.Element>().map((e) => e.tag).toList();
      expect(tags.contains('math'), isFalse);
      final text = nodes.map((n) => n.textContent).join();
      expect(text.contains('100'), isTrue);
    });

    test('块级公式 \$\$...\$\$ 生成 mathblock 节点', () {
      final nodes = doc.parseInline(r'$$\int_0^1 x^2 dx$$');
      final tags =
          nodes.whereType<m.Element>().map((e) => e.tag).toList();
      expect(tags.contains('mathblock'), isTrue);
    });
  });
}
