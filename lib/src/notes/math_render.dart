import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:markdown/markdown.dart' as m;
import 'package:markdown_widget/markdown_widget.dart';

import '../ui/h_scrollbar.dart';

/// 行内公式：`$...$`（非贪婪，不匹配 `$100` 纯数字金额）。
class MathInlineSyntax extends m.InlineSyntax {
  MathInlineSyntax() : super(r'\$([^$\n]+?)\$');

  @override
  bool onMatch(m.InlineParser parser, Match match) {
    final tex = match.group(1)!;
    parser.addNode(m.Element.text('math', tex));
    return true;
  }
}

/// 块级公式：`$$...$$`（允许跨行）。
class MathBlockSyntax extends m.InlineSyntax {
  MathBlockSyntax() : super(r'\$\$([\s\S]+?)\$\$');

  @override
  bool onMatch(m.InlineParser parser, Match match) {
    final tex = match.group(1)!;
    parser.addNode(m.Element.text('mathblock', tex));
    return true;
  }
}

/// math/mathblock 节点 → KaTeX widget。
class MathNode extends SpanNode {
  MathNode(this.tex, {this.display = false});

  final String tex;
  final bool display;

  @override
  InlineSpan build() {
    try {
      final math = Math.tex(
        tex,
        mathStyle: display ? MathStyle.display : MathStyle.text,
        textStyle: style ?? const TextStyle(fontSize: 15),
      );
      // 块级公式超宽时横向滚动而非截断（与代码块同一模式）；
      // 行内公式保持随文流式排版
      final Widget child = display
          ? LayoutBuilder(
              builder: (context, constraints) =>
                  constraints.maxWidth.isFinite
                      ? HScrollbar(bottomPadding: 2, child: math)
                      : math,
            )
          : math;
      return WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: child,
      );
    } on Object {
      // 解析失败时回退为等宽文本，避免整页崩溃
      return TextSpan(
        text: display ? '\$\$$tex\$\$' : '\$$tex\$',
        style: (style ?? const TextStyle()).copyWith(
          fontFamily: 'monospace',
          fontSize: 13,
        ),
      );
    }
  }
}
