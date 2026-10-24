/// 从 Markdown 文本提取标题生成目录（跳过代码块内的 # 行）。
library;

/// 一个目录条目。
class TocEntry {
  const TocEntry({
    required this.level,
    required this.text,
    this.line = 0,
  });

  /// 标题层级 1-6。
  final int level;

  /// 标题文本（去掉了 # 与尾随 #）。
  final String text;

  /// 标题行在原文中的索引（0 基，按 '\n' 切分）；0 表示未知。
  /// 供文内搜索按章节定位。
  final int line;
}

final _fenceOpen = RegExp(r'^(`{3,}|~{3,})');
final _heading = RegExp(r'^(#{1,6})\s+(.+?)\s*#*\s*$');
final _setext1 = RegExp(r'^=+[ \t]*$');
final _setext2 = RegExp(r'^-+[ \t]*$');
final _notSetextBody = RegExp(r'^(?:[-*+]|\d+[.)])[ \t]|^>');

/// 提取全部标题（ATX `#` 与 setext `===`/`---` 下划线两种形式），保持出现顺序。
///
/// setext 支持不是锦上添花：markdown_widget 挂锚点时按它自己识别出的
/// 标题序列计数，若这里少算 setext 标题，锚点索引整体错位，TOC 跳转
/// 就会落到错误的标题上。
///
/// 围栏判定按 CommonMark，而不是「见 ``` 就翻转」：
/// - 开栏的 info string 不能包含围栏字符本身（`` ```text``` `` 这类
///   行内代码不是围栏；波浪线围栏无此限制，info 可含反引号）；
/// - 闭栏必须与开栏同字符、长度不小于开栏，且其后只允许空白。
/// 否则形如 `` ```……``` `` 的注释行会被误判为闭栏，围栏状态从此
/// 整体反转，代码块里的 `# 注释` 被当成标题混入 TOC。
List<TocEntry> extractToc(String markdown) {
  final entries = <TocEntry>[];
  var fenceChar = '';
  var fenceLen = 0;
  // 上一段非空普通文本（setext 标题体），空行/围栏行/标题行会清掉
  String? pendingText;
  var pendingLine = -1;
  final lines = markdown.split('\n');
  for (var i = 0; i < lines.length; i++) {
    // trimRight 去掉 CRLF 的 '\r'（Windows 仓库常见），否则闭栏正则
    // `[ \t]*$` 匹配不上 '```\r'，围栏永不闭合
    final trimmed = lines[i].trim();
    if (fenceChar.isEmpty) {
      final m = _fenceOpen.firstMatch(trimmed);
      if (m != null) {
        final marker = m.group(1)!;
        final rest = trimmed.substring(marker.length);
        final canOpen = marker[0] == '~' || !rest.contains('`');
        if (canOpen) {
          fenceChar = marker[0];
          fenceLen = marker.length;
          pendingText = null;
          continue;
        }
      }
    } else {
      final m = RegExp(
        '^${RegExp.escape(fenceChar)}{$fenceLen,}[ \t]*\$',
      ).firstMatch(trimmed);
      if (m != null) {
        fenceChar = '';
        fenceLen = 0;
      }
      // 围栏内一律跳过（无论本行是否为闭栏）
      continue;
    }
    final h = _heading.firstMatch(trimmed);
    if (h != null) {
      final text = h.group(2)!.trim();
      if (text.isNotEmpty) {
        entries.add(TocEntry(
          level: h.group(1)!.length,
          text: text,
          line: i,
        ));
      }
      pendingText = null;
      continue;
    }
    // setext 下划线：前一行是非空普通文本时，=== 为 H1、--- 为 H2。
    // 单独出现的 ---/=== 是分隔线，不构成标题。
    if (trimmed.isNotEmpty && pendingText != null) {
      final isSetext1 = _setext1.hasMatch(trimmed);
      final isSetext2 = _setext2.hasMatch(trimmed);
      if (isSetext1 || isSetext2) {
        entries.add(TocEntry(
          level: isSetext1 ? 1 : 2,
          text: pendingText,
          line: pendingLine,
        ));
        pendingText = null;
        continue;
      }
    }
    if (trimmed.isEmpty) {
      pendingText = null;
    } else if (_notSetextBody.hasMatch(trimmed)) {
      // 列表项/引用行不构成 setext 标题体（CommonMark：其后 --- 是分隔线）
      pendingText = null;
    } else {
      pendingText = trimmed;
      pendingLine = i;
    }
  }
  return entries;
}
