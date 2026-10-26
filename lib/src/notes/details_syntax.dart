import 'package:markdown/markdown.dart' as m;

/// `<details>` 折叠块语法：markdown 包把未知块级 HTML（含 details）解析成
/// 原始文本，不会产出 Element，包默认渲染即纯文本。此语法拦截 details
/// 块，产出 Element(tag: 'details')，内部行按 Markdown 正常解析（代码块/
/// 表格/列表保留渲染），`<summary>` 行提取为 summary 子元素——
/// markdown_viewer 注册同 tag 的自定义 SpanNode 接住渲染。
///
/// 支持的写法（与 notes 仓库实际用法一致）：
/// - `<details>` 单独成行 / 带属性如 `<details open>`
/// - `<summary>标题</summary>` 单独成行，或与开标签同行
///   `<details><summary>答案</summary>`
/// - 嵌套 `<details>`（按开闭计数配对）
class DetailsBlockSyntax extends m.BlockSyntax {
  static final _openTag = RegExp(r'<details\b([^>]*)>', caseSensitive: false);
  static final _summaryLine =
      RegExp(r'^\s*<summary>(.*?)</summary>\s*$', caseSensitive: false);

  @override
  RegExp get pattern => RegExp(r'^\s*<details\b', caseSensitive: false);

  @override
  bool canParse(m.BlockParser parser) =>
      pattern.hasMatch(parser.current.content);

  @override
  m.Node? parse(m.BlockParser parser) {
    final inner = <String>[];
    var depth = 0;
    var open = false;
    var closed = false;

    // 收集到配对的 </details>；首行剥开标签（可能附带 <summary>…）
    while (!parser.isDone) {
      var line = parser.current.content;
      parser.advance();

      if (depth == 0) {
        final m = _openTag.firstMatch(line);
        if (m == null) return null; // 非法首行，交回其他语法
        open = open || RegExp(r'\bopen\b').hasMatch(m.group(1) ?? '');
        line = line.replaceFirst(_openTag, '');
        depth = 1; // 首行已计入开标签
        if (line.trim().isEmpty) continue;
      }

      // 嵌套计数：开标签 +1，闭标签 -1；闭标签行剥掉后残余内容保留
      final opens = _openTag.allMatches(line).length;
      final closes = RegExp(r'</details\s*>', caseSensitive: false)
          .allMatches(line)
          .length;
      depth += opens;
      if (closes > 0) {
        depth -= closes;
        if (depth <= 0) {
          line = line.replaceFirst(
              RegExp(r'</details\s*>', caseSensitive: false), '');
          if (line.trim().isNotEmpty) inner.add(line);
          closed = true;
          break;
        }
      }
      inner.add(line);
    }
    if (!closed) return null; // 没有闭标签，不吞块（回退原渲染）

    // 提取 <summary> 行（单行完整开闭；真实笔记均为该形式）
    String? summaryText;
    final content = <String>[];
    for (final l in inner) {
      final s = _summaryLine.firstMatch(l);
      if (s != null && summaryText == null) {
        summaryText = s.group(1);
        continue;
      }
      content.add(l);
    }

    final children = <m.Node>[
      if (summaryText != null)
        m.Element('summary', parser.document.parseInline(summaryText)),
      ...parser.document.parseLines(content),
    ];
    final el = m.Element('details', children);
    if (open) el.attributes['open'] = 'open';
    return el;
  }
}
