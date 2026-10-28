import 'package:flutter/material.dart';

import '../search/text_search.dart';

/// 检索摘要的统一样式：命中处用主题色底 + 加粗高亮。
///
/// 偏移由检索层给出（[SearchSnippet.matchStart]/[matchLength]），
/// 这里不做二次匹配，避免大小写/编码差异导致高亮错位。
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
    final start = snippet.matchStart.clamp(0, text.length).toInt();
    final end =
        (snippet.matchStart + snippet.matchLength).clamp(start, text.length)
            .toInt();
    return Text.rich(
      TextSpan(
        children: [
          if (start > 0) TextSpan(text: text.substring(0, start), style: base),
          if (end > start)
            TextSpan(text: text.substring(start, end), style: hit),
          if (end < text.length)
            TextSpan(text: text.substring(end), style: base),
        ],
      ),
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
    );
  }
}
