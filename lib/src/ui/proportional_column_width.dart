import 'dart:math' as math;

import 'package:flutter/rendering.dart';

/// 按内容比例分配列宽：每列的 flex 权重 = 该列最宽单元格的固有内容宽度
/// （测量自渲染树，非文本估算）。
///
/// 用于 wrap 档表格：总宽被外层 SizedBox 约束后，各列按内容宽度比例分摊，
/// 序号等窄列不再被均分拉宽；单元格在列宽内自动换行。
///
/// [minCellWidth] 为可选的列宽下限（单元格固有宽，含内边距）。两位数字序号
/// （`01`…`99`）等极窄内容按纯比例分摊时会被压到换行，给定下限（约 2 个
/// 汉字宽 = 2×字号 + 单元格水平内边距）后，收缩阶段窄列停在下限不再换行。
/// 实现：maxIntrinsicWidth 抬到下限让总宽超出目标宽，触发 RenderTable 的
/// 收缩步（step 4），此时 minWidths（同样抬到下限）兜住窄列。
class ProportionalColumnWidth extends IntrinsicColumnWidth {
  const ProportionalColumnWidth({this.minCellWidth});

  /// 列宽下限（null = 不设下限，纯比例分摊）。
  final double? minCellWidth;

  double _widest(Iterable<RenderBox> cells) {
    var widest = 0.0;
    for (final cell in cells) {
      widest = math.max(widest, cell.getMaxIntrinsicWidth(double.infinity));
    }
    return widest;
  }

  // 与 FlexColumnWidth 同理：固有宽度必须报 0，否则「剩余空间」为零，
  // flex 分摊会被布局算法跳过、列宽退回各自的自然宽度（总宽溢出容器）。
  // 返回值同时是 RenderTable 收缩步（step 4）的下限：内容列抬到
  // max(最长词宽, minCellWidth)——窄序号列停在下限不换行，宽列仍可
  // 换行收缩、只保住最长不可断词。
  @override
  double minIntrinsicWidth(Iterable<RenderBox> cells, double containerWidth) {
    final floor = minCellWidth;
    if (floor == null) return 0;
    // 内容为空的占位列不设下限（保持 0，不参与分摊）
    if (_widest(cells) <= 0) return 0;
    return math.max(super.minIntrinsicWidth(cells, containerWidth), floor);
  }

  @override
  double maxIntrinsicWidth(Iterable<RenderBox> cells, double containerWidth) {
    final widest = _widest(cells);
    final floor = minCellWidth;
    if (floor != null && widest > 0 && widest < floor) return floor;
    return widest;
  }

  @override
  double? flex(Iterable<RenderBox> cells) {
    final widest = _widest(cells);
    // 内容为空的占位列不参与分摊（flex = 0 会被视为不可用，返回 null 走固有宽度）
    return widest > 0 ? widest : null;
  }
}
