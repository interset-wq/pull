/// 正文检索的纯逻辑（不碰文件系统，便于单测）：在单个文本里找命中、
/// 统计次数、截取带上下文的摘要片段。
library;

/// 一条命中摘要：命中所在行的截断文本 + 命中在片段内的偏移与长度
/// （供 UI 高亮，避免二次匹配导致大小写不一致）。
class SearchSnippet {
  const SearchSnippet({
    required this.line,
    required this.text,
    required this.matchStart,
    required this.matchLength,
  });

  /// 命中所在行号（0 基）。
  final int line;

  /// 截断后的行文本（首尾可能带省略号）。
  final String text;

  /// 命中在 [text] 中的起始下标。
  final int matchStart;

  /// 命中长度。
  final int matchLength;
}

/// 单个文件的检索结果。
class FileSearchResult {
  const FileSearchResult({
    required this.relativePath,
    required this.matches,
    required this.snippets,
  });

  final String relativePath;

  /// 命中总次数（同一行多处会分别计数）。
  final int matches;

  /// 最多 [maxSnippets] 条摘要，按出现顺序。
  final List<SearchSnippet> snippets;
}

/// 摘要最长字符数：太长会把列表撑爆，太短又看不出上下文。
const int _snippetMaxChars = 100;

/// 在 [content] 中检索 [query]（大小写不敏感，中文按原文直接匹配）。
///
/// 没有命中返回 null。命中行去重后最多取 [maxSnippets] 条摘要，
/// 但 [FileSearchResult.matches] 统计所有命中。
FileSearchResult? searchInText({
  required String relativePath,
  required String content,
  required String query,
  int maxSnippets = 3,
}) {
  final q = query.trim();
  if (q.isEmpty || content.isEmpty) return null;
  final needle = q.toLowerCase();
  final haystack = content.toLowerCase();
  final lineStarts = _lineStarts(content);
  final snippets = <SearchSnippet>[];
  var matches = 0;
  var from = 0;
  while (from <= haystack.length - needle.length) {
    final at = haystack.indexOf(needle, from);
    if (at < 0) break;
    matches++;
    final line = _lineOf(lineStarts, at);
    if (snippets.length < maxSnippets &&
        !snippets.any((s) => s.line == line)) {
      snippets.add(_snippetAt(content, lineStarts, line, at, needle.length));
    }
    // 按命中长度前进：同一处不重复计数（"aa" 里找 "aa" 是 1 次）
    from = at + needle.length;
  }
  if (matches == 0) return null;
  return FileSearchResult(
    relativePath: relativePath,
    matches: matches,
    snippets: snippets,
  );
}

/// 文内查找的一处命中。
class TextMatch {
  const TextMatch({
    required this.offset,
    required this.line,
    required this.lineText,
  });

  /// 在全文中的字符下标。
  final int offset;

  /// 所在行（0 基），与 `extractToc` 的行号同一坐标系，便于按章节定位。
  final int line;

  /// 该行原文（已去首尾空白），用于查找条里的上下文预览。
  final String lineText;
}

/// 找出 [text] 中 [query] 的全部命中（大小写不敏感、按出现顺序）。
///
/// 供阅读页「文内查找」使用：命中按行号返回，调用方再按 TOC 的
/// `TocEntry.line` 定位到所在章节滚动。
List<TextMatch> findTextMatches(String text, String query) {
  final q = query.trim();
  if (q.isEmpty || text.isEmpty) return const [];
  final needle = q.toLowerCase();
  final haystack = text.toLowerCase();
  if (needle.length > haystack.length) return const [];
  final lineStarts = _lineStarts(text);
  final out = <TextMatch>[];
  var from = 0;
  while (from <= haystack.length - needle.length) {
    final at = haystack.indexOf(needle, from);
    if (at < 0) break;
    final line = _lineOf(lineStarts, at);
    out.add(
      TextMatch(
        offset: at,
        line: line,
        lineText: _lineText(text, lineStarts, line).trim(),
      ),
    );
    from = at + needle.length;
  }
  return out;
}

/// 取第 [line] 行的原文（不含换行符；CRLF 会去掉 `\r`）。
String _lineText(String content, List<int> starts, int line) {
  final lineStart = starts[line];
  var lineEnd = line + 1 < starts.length ? starts[line + 1] - 1 : content.length;
  if (lineEnd > lineStart && content.codeUnitAt(lineEnd - 1) == 0x0D) {
    lineEnd--;
  }
  return content.substring(lineStart, lineEnd);
}

/// 每行起始下标（0 基），用于把字符下标换算成行号。
List<int> _lineStarts(String content) {
  final starts = <int>[0];
  for (var i = 0; i < content.length; i++) {
    if (content.codeUnitAt(i) == 0x0A) starts.add(i + 1);
  }
  return starts;
}

/// 二分查找 [offset] 所在行。
int _lineOf(List<int> starts, int offset) {
  var lo = 0;
  var hi = starts.length - 1;
  while (lo < hi) {
    final mid = (lo + hi + 1) >> 1;
    if (starts[mid] <= offset) {
      lo = mid;
    } else {
      hi = mid - 1;
    }
  }
  return lo;
}

SearchSnippet _snippetAt(
  String content,
  List<int> starts,
  int line,
  int matchAt,
  int matchLength,
) {
  final lineStart = starts[line];
  final raw = _lineText(content, starts, line);
  final matchInLine = matchAt - lineStart;

  // 行太长时围绕命中位置截断，保证命中一定落在片段里
  if (raw.length <= _snippetMaxChars) {
    return SearchSnippet(
      line: line,
      text: raw.trimLeft(),
      matchStart: matchInLine - (raw.length - raw.trimLeft().length),
      matchLength: matchLength,
    );
  }
  const context = 30;
  var begin = matchInLine - context;
  if (begin < 0) begin = 0;
  var end = begin + _snippetMaxChars;
  if (end > raw.length) {
    end = raw.length;
    begin = end - _snippetMaxChars;
    if (begin < 0) begin = 0;
  }
  final prefix = begin > 0 ? '…' : '';
  final suffix = end < raw.length ? '…' : '';
  final cut = raw.substring(begin, end);
  return SearchSnippet(
    line: line,
    text: '$prefix$cut$suffix',
    matchStart: prefix.length + (matchInLine - begin),
    matchLength: matchLength,
  );
}
