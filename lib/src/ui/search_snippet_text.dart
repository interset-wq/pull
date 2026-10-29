import 'package:flutter/material.dart';

import '../search/text_search.dart';

/// 检索摘要的统一样式：命中处用主题色底 + 加粗高亮。
///
/// 偏移由检索层给出（[SearchSnippet.highlights]），这里不做二次匹配，
/// 避免大小写/编码差异导致高亮错位；多词检索时一段摘要里可能有多处。
class SearchSnippetText extends StatelessWidget {
  const SearchSnippetText({
    required this.snippet,
    this.maxLines = 2,
    super.key,
  });

  final SearchSnippet snippet;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      height: 1.3,
    );
    final hit = base?.copyWith(
      color: theme.colorScheme.onPrimaryContainer,
      backgroundColor: theme.colorScheme.primaryContainer,
      fontWeight: FontWeight.w600,
    );
    final text = snippet.text;
    final highlights = [...snippet.highlights]
      ..sort((a, b) => a.start.compareTo(b.start));
    final spans = <TextSpan>[];
    var cursor = 0;
    for (final highlight in highlights) {
      final start = highlight.start.clamp(0, text.length);
      final end = (highlight.start + highlight.length).clamp(start, text.length);
      // 重叠区间（例如同时搜 "ab" 与 "bc"）只保留第一段，避免样式打架
      if (start < cursor || end <= start) continue;
      if (start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, start), style: base));
      }
      spans.add(TextSpan(text: text.substring(start, end), style: hit));
      cursor = end;
    }
    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor), style: base));
    }
    return Text.rich(
      TextSpan(children: spans),
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
    );
  }
}
