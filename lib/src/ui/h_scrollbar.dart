import 'package:flutter/material.dart';

/// 超宽内容（代码块/表格）的水平滚动容器：
/// 滚动条不叠加在内容上（Material Scrollbar 的滑块锚定在视口底缘，
/// 必然遮挡最后一行），而是自绘一条位于内容下方专用条带里的滑块，
/// 紧贴块底部且绝不遮挡文字，支持拖拽。
class HScrollbar extends StatefulWidget {
  const HScrollbar({
    required this.child,
    super.key,
    this.bottomPadding = 0,
    this.onOverflow,
  });

  final Widget child;

  /// 内容下方滚动条条带高度（0 = 不显示条带，仅保留滚动能力）。
  final double bottomPadding;

  /// 首帧布局后回调一次：`maxScrollExtent` = 内容自然宽度 − 视口宽
  /// （无溢出为 0）。供上层做两档渲染判定，滚动中不再重复触发。
  final ValueChanged<double>? onOverflow;

  @override
  State<HScrollbar> createState() => _HScrollbarState();
}

class _HScrollbarState extends State<HScrollbar> {
  final _controller = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controller.hasClients) return;
      final pos = _controller.position;
      if (!pos.hasContentDimensions) return;
      widget.onOverflow?.call(pos.maxScrollExtent);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bar = widget.bottomPadding;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            controller: _controller,
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              // 块元素化：内容至少占满视口宽度，少内容的代码块不再缩成窄条
              constraints: BoxConstraints(minWidth: constraints.maxWidth),
              child: widget.child,
            ),
          ),
        ),
        if (bar > 0)
          _HScrollTrack(
            controller: _controller,
            height: bar,
            thumbColor: Theme.of(context).colorScheme.outline,
          ),
      ],
    );
  }
}

/// 自绘水平滚动条：内容下方条带内的圆角滑块，随滚动位置移动，可拖拽。
class _HScrollTrack extends StatelessWidget {
  const _HScrollTrack({
    required this.controller,
    required this.height,
    required this.thumbColor,
  });

  final ScrollController controller;
  final double height;
  final Color thumbColor;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final trackW = constraints.maxWidth - 8;
            final pos =
                controller.hasClients ? controller.position : null;
            if (pos == null ||
                !pos.hasContentDimensions ||
                pos.maxScrollExtent <= 0) {
              return SizedBox(height: height);
            }
            final thumbW = (pos.viewportDimension /
                    (pos.maxScrollExtent + pos.viewportDimension) *
                    trackW)
                .clamp(40.0, trackW)
                .toDouble();
            final frac = (pos.pixels / pos.maxScrollExtent).clamp(0.0, 1.0);
            return SizedBox(
              height: height,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragUpdate: (d) {
                  final range = trackW - thumbW;
                  if (range <= 0) return;
                  final next = pos.pixels + d.delta.dx / range * pos.maxScrollExtent;
                  controller.position.jumpTo(
                    next.clamp(0.0, pos.maxScrollExtent),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Align(
                    alignment: Alignment(frac * 2 - 1, 0),
                    child: Container(
                      width: thumbW,
                      height: 4,
                      decoration: BoxDecoration(
                        color: thumbColor,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
