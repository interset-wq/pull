/// 表格自然宽度估算（文档级两档渲染的判定依据）。
///
/// 渲染策略（经用户确认）：
/// - 表格自然宽度 ≤ 2 倍屏宽：保留固有列宽 + 横向滚动，不换行
///   （最多 2 屏宽，滚动距离可控）；
/// - 自然宽度 > 2 倍屏宽：FlexColumnWidth，表格固定为 2 倍屏宽，
///   单元格在 2 屏宽内强制换行；横滚条保留。
///
/// 宽度为估算值（CJK ≈ 1em、ASCII ≈ 0.55em、行内代码 ≈ 0.6em），
/// 精度 ±20%，只用于 2 倍屏宽这一档的判定，贴线误判影响可接受。
library;

/// 每个单元格水平内边距（headPadding/bodyPadding 左右各 8）。
const double _cellHPadding = 16;
/// 边框线宽。
const double _borderWidth = 1;

/// 估算文档中最宽表格的自然宽度（px）；无表格返回 0。
double estimateTableNaturalWidth(String body, double fontSize) {
  var inFence = false;
  final colMax = <int, double>{};
  var best = 0.0;
  for (final raw in body.split('\n')) {
    final line = raw.trim();
    if (line.startsWith('```') || line.startsWith('~~~')) {
      inFence = !inFence;
      colMax.clear();
      continue;
    }
    if (inFence || !line.startsWith('|') || _isSeparatorRow(line)) {
      colMax.clear();
      continue;
    }
    _accumulateRow(line, colMax, fontSize);
    var w = 0.0;
    for (final v in colMax.values) {
      w += v;
    }
    best = w > best ? w : best;
  }
  return best;
}

/// 逐列取最大单元格宽度（列宽 = 该列最宽单元格）。
void _accumulateRow(String line, Map<int, double> colMax, double fontSize) {
  final cells = line.split('|');
  // 去掉首尾 `|` 产生的空项
  if (cells.isNotEmpty && cells.first.trim().isEmpty) cells.removeAt(0);
  if (cells.isNotEmpty && cells.last.trim().isEmpty) cells.removeLast();
  for (var i = 0; i < cells.length; i++) {
    final w =
        _estimateCellWidth(cells[i].trim(), fontSize) +
        _cellHPadding +
        _borderWidth;
    final prev = colMax[i];
    if (prev == null || w > prev) colMax[i] = w;
  }
}

double _estimateCellWidth(String cell, double fontSize) {
  var total = 0.0;
  var inCode = false;
  for (final rune in cell.runes) {
    final r = rune;
    if (r == 0x60) {
      inCode = !inCode;
      total += 0.6 * fontSize;
      continue;
    }
    // CJK / 全角字符 ≈ 1em，其余（拉丁、数字、空格、标点）≈ 0.55em
    final isWide = r >= 0x2E80 && r <= 0x9FFF ||
        r >= 0xAC00 && r <= 0xD7A3 ||
        r >= 0xF900 && r <= 0xFAFF ||
        r >= 0xFF01 && r <= 0xFF60;
    total += (isWide ? 1.0 : (inCode ? 0.6 : 0.55)) * fontSize;
  }
  return total;
}

bool _isSeparatorRow(String line) {
  if (!line.contains('-')) return false;
  for (final c in line.split('')) {
    if (c != '|' && c != '-' && c != ':' && c != ' ' && c != '\t') {
      return false;
    }
  }
  return true;
}
