/// 文档级表格渲染策略判定。
///
/// markdown_widget 的表格默认 `IntrinsicColumnWidth`：列宽 = 内容固有
/// 宽度，文本不换行，纯文本表格会被撑出屏幕、横滚条很长。改为
/// `FlexColumnWidth` 后文本换行、表格铺满屏宽。
///
/// 但含长代码 / 长不可断行串 / 列数过多的表格换行会溢出或被截断，
/// 必须保留横滚。本文件按文档内容二选一（TableConfig 作用于整篇文档
/// 的所有表格，粒度到不了单表）：
///
/// 判定为 [TableLayout.scroll]（保留固有列宽 + 横向滚动）的条件，满足其一：
/// - 任一行超过 5 列；
/// - 任一格含 ≥16 字符的行内代码；
/// - 任一格含 ≥24 字符的连续不可断行串（长 URL / 长标识符 / 长路径）。
library;

enum TableLayout { wrap, scroll }

/// 表格分隔行的特征：只含 `|`、`-`、`:`、空格，且至少一个 `-`。
final RegExp _separatorRow = RegExp(r'^\s*\|?[\s:|-]*-[\s:|-]*$');

TableLayout detectTableLayout(String body) {
  var inFence = false;
  for (final raw in body.split('\n')) {
    final line = raw.trim();
    if (line.startsWith('```') || line.startsWith('~~~')) {
      inFence = !inFence;
      continue;
    }
    if (inFence || !line.startsWith('|')) continue;
    if (_separatorRow.hasMatch(line)) continue;
    final cells = _splitRow(line);
    if (cells.length > 5) return TableLayout.scroll;
    for (final cell in cells) {
      // 行内代码：`...`
      if (RegExp(r'`[^`\n]{16,}`').hasMatch(cell)) return TableLayout.scroll;
      // 连续不可断行串（ASCII 无空格长串：URL / 代码 / 路径）
      if (RegExp(r'[A-Za-z0-9_./\\-]{24,}').hasMatch(cell)) {
        return TableLayout.scroll;
      }
    }
  }
  return TableLayout.wrap;
}

/// 拆一行表格为单元格列表（去掉首尾 `|` 产生的空项）。
List<String> _splitRow(String line) {
  final parts = line.split('|');
  if (parts.isNotEmpty && parts.first.trim().isEmpty) parts.removeAt(0);
  if (parts.isNotEmpty && parts.last.trim().isEmpty) parts.removeLast();
  return parts;
}
