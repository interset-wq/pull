import 'dart:math' as math;

import 'package:flutter/rendering.dart';

/// 按内容比例分配列宽：每列的 flex 权重 = 该列最宽单元格的固有内容宽度
/// （测量自渲染树，非文本估算）。
///
/// 用于 wrap 档表格：总宽被外层 SizedBox 约束后，各列按内容宽度比例分摊，
/// 序号等窄列不再被均分拉宽；单元格在列宽内自动换行。
class ProportionalColumnWidth extends IntrinsicColumnWidth {
  const ProportionalColumnWidth();

  // 与 FlexColumnWidth 同理：固有宽度必须报 0，否则「剩余空间」为零，
  // flex 分摊会被布局算法跳过、列宽退回各自的自然宽度（总宽溢出容器）
  @override
  double minIntrinsicWidth(Iterable<RenderBox> cells, double containerWidth) => 0;

  @override
  double maxIntrinsicWidth(Iterable<RenderBox> cells, double containerWidth) => 0;

  @override
  double? flex(Iterable<RenderBox> cells) {
    var widest = 0.0;
    for (final cell in cells) {
      widest = math.max(widest, cell.getMaxIntrinsicWidth(double.infinity));
    }
    // 内容为空的占位列不参与分摊（flex = 0 会被视为不可用，返回 null 走固有宽度）
    return widest > 0 ? widest : null;
  }
}
