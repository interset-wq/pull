/// GitHub Flavored Markdown 提示块（`> [!NOTE]` 等）的解析与分割。
library;

/// GFM 告警类型及其展示样式。
enum GfmAlertType {
  note('NOTE', '注', 0xff0969da),
  tip('TIP', '提示', 0xff1a7f37),
  important('IMPORTANT', '重要', 0xff8250df),
  warning('WARNING', '警告', 0xff9a6700),
  caution('CAUTION', '注意', 0xffcf222e);

  const GfmAlertType(this.tag, this.title, this.color);

  final String tag;
  final String title;
  final int color;
}

/// 正文分割出的一段：普通 Markdown 或 GFM 告警块。
sealed class MarkdownSegment {
  const MarkdownSegment();
}

/// 普通 Markdown 文本段。
class TextSegment extends MarkdownSegment {
  const TextSegment(this.text);

  final String text;
}

/// GFM 告警块。
class AlertSegment extends MarkdownSegment {
  const AlertSegment(this.type, this.body);

  final GfmAlertType type;

  /// 告警正文（已剥除 blockquote 前缀的 Markdown 文本）。
  final String body;
}

/// 把 Markdown 源文本按 GFM 告警块分割成段。
List<MarkdownSegment> splitGfmAlerts(String source) {
  final segments = <MarkdownSegment>[];
  final lines = source.split('\n');
  var buffer = <String>[];

  void flush() {
    if (buffer.isNotEmpty) {
      segments.add(TextSegment(buffer.join('\n')));
      buffer = [];
    }
  }

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final alert = _matchAlertStart(line);
    if (alert == null) {
      buffer.add(line);
      continue;
    }
    // 收集连续的 blockquote 行作为告警块
    final body = <String>[];
    var j = i + 1;
    while (j < lines.length && lines[j].trimLeft().startsWith('>')) {
      body.add(_stripQuote(lines[j]));
      j++;
    }
    // 告警块后保留一个空行，与后续段落分隔
    flush();
    segments.add(AlertSegment(alert, body.join('\n').trim()));
    i = j - 1;
  }
  flush();
  return segments;
}

/// 匹配 `> [!TYPE]` 形式的告警起始行，返回类型，否则返回 null。
GfmAlertType? _matchAlertStart(String line) {
  final m = RegExp(r'^>\s*\[!(\w+)\]\s*$', caseSensitive: false).firstMatch(line);
  if (m == null) return null;
  final tag = m.group(1)!.toUpperCase();
  for (final t in GfmAlertType.values) {
    if (t.tag == tag) return t;
  }
  return null;
}

/// 剥除一行 blockquote 前缀（`>` + 可选空格）。
String _stripQuote(String line) {
  final l = line.trimLeft();
  if (l.startsWith('> ')) return l.substring(2);
  if (l.startsWith('>')) return l.substring(1);
  return line;
}
