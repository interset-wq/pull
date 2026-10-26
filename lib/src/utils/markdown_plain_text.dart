import 'package:markdown/markdown.dart' as m;

/// Markdown → 纯文本（Roadmap「导出与分享·复制纯文本」）：
/// 复用渲染管线的 GFM 解析（github-flavored 扩展集），按块级结构提取：
/// 标题/段落间空行分隔；代码块保留内容；图片用 alt 文本；链接保留链接
/// 文字（丢 URL）；列表保留标记并缩进嵌套层；表格行用 ` | ` 连接单元格。
String markdownToPlainText(String source) =>
    _extractBlocks(source).join('\n\n');

List<String> _extractBlocks(String source) {
  final doc = m.Document(
    extensionSet: m.ExtensionSet.gitHubFlavored,
    encodeHtml: false,
  );
  final lines = source.split(RegExp(r'(\r?\n)|(\r)'));
  final blocks = doc.parseLines(lines);
  final out = <String>[];
  for (final node in blocks) {
    _walkBlock(node, out, depth: 0);
  }
  return out.map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
}

void _walkBlock(
  m.Node node,
  List<String> out, {
  required int depth,
}) {
  if (node is m.Text) {
    final t = node.text.trim();
    if (t.isNotEmpty) out.add(t);
    return;
  }
  if (node is! m.Element) return;
  final indent = '  ' * depth;
  switch (node.tag) {
    case 'h1' || 'h2' || 'h3' || 'h4' || 'h5' || 'h6':
      out.add(_inline(node));
    case 'p':
      out.add(_inline(node));
    case 'pre':
      // 代码块内容原样保留（textContent 已含换行）
      final t = node.textContent;
      out.add(t.trimRight());
    case 'blockquote':
      final inner = <String>[];
      for (final c in node.children ?? const <m.Node>[]) {
        _walkBlock(c, inner, depth: depth);
      }
      if (inner.isEmpty) break;
      // 保留引用标记
      out.add(inner.map((s) => '> $s').join('\n> '));
    case 'ul' || 'ol':
      var i = 0;
      for (final li in node.children ?? const <m.Node>[]) {
        if (li is! m.Element || li.tag != 'li') continue;
        i++;
        final marker = node.tag == 'ol' ? '$i. ' : '- ';
        // 行内内容并进标记行；嵌套块（段落/子列表/代码块）换行续排
        final parts = <String>[];
        for (final c in li.children ?? const <m.Node>[]) {
          final nested = c is m.Element &&
              const {
                'p', 'ul', 'ol', 'pre', 'blockquote',
                'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'table',
              }.contains(c.tag);
          if (nested) {
            _walkBlock(c, parts, depth: depth + 1);
          } else {
            final t = _inline(c).trim();
            if (t.isNotEmpty) parts.add(t);
          }
        }
        out.add('$indent$marker${parts.isEmpty ? '' : parts.first}');
        for (final extra in parts.skip(1)) {
          out.add('$indent  $extra');
        }
      }
    case 'table':
      for (final row in node.children ?? const <m.Node>[]) {
        if (row is! m.Element || row.tag != 'thead' && row.tag != 'tbody') {
          continue;
        }
        for (final tr in row.children ?? const <m.Node>[]) {
          if (tr is! m.Element || tr.tag != 'tr') continue;
          final cells = <String>[];
          for (final td in tr.children ?? const <m.Node>[]) {
            if (td is m.Element) cells.add(_inline(td).trim());
          }
          if (cells.isNotEmpty) out.add(cells.join(' | '));
        }
      }
    case 'hr':
      break; // 分隔线在纯文本里没有意义，跳过
    default:
      // 未知块级标签（html 块等）：尽力提取文本
      final t = _inline(node).trim();
      if (t.isNotEmpty) out.add(t);
  }
}

/// 行内内容提取：文本/加粗/斜体/链接文字，图片取 alt，`<br>` 转换行。
String _inline(m.Node node) {
  if (node is m.Text) return node.text;
  if (node is m.Element) {
    if (node.tag == 'img') return node.attributes['alt'] ?? '';
    if (node.tag == 'br') return '\n';
    if (node.tag == 'a') return _inline(node.children?.first ?? node);
    return node.children?.map(_inline).join() ?? '';
  }
  return '';
}
