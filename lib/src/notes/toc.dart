/// 从 Markdown 文本提取标题生成目录（跳过代码块内的 # 行）。
library;

/// 一个目录条目。
class TocEntry {
  const TocEntry({required this.level, required this.text});

  /// 标题层级 1-6。
  final int level;

  /// 标题文本（去掉了 # 与尾随 #）。
  final String text;
}

/// 提取全部 ATX 标题（# 形式），保持出现顺序。
List<TocEntry> extractToc(String markdown) {
  final entries = <TocEntry>[];
  var inFence = false;
  for (final line in markdown.split('\n')) {
    final trimmed = line.trimLeft();
    if (trimmed.startsWith('```') || trimmed.startsWith('~~~')) {
      inFence = !inFence;
      continue;
    }
    if (inFence) continue;
    final m = RegExp(r'^(#{1,6})\s+(.+?)\s*#*\s*$').firstMatch(trimmed);
    if (m != null) {
      final text = m.group(2)!.trim();
      if (text.isNotEmpty) {
        entries.add(TocEntry(level: m.group(1)!.length, text: text));
      }
    }
  }
  return entries;
}
