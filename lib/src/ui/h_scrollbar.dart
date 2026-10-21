import 'package:flutter/material.dart';

/// 超宽内容（代码块/表格）的水平滚动容器：带可见滚动条，
/// 确保内容不截断、不强制换行。
class HScrollbar extends StatefulWidget {
  const HScrollbar({required this.child, super.key});

  final Widget child;

  @override
  State<HScrollbar> createState() => _HScrollbarState();
}

class _HScrollbarState extends State<HScrollbar> {
  final _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      controller: _controller,
      thumbVisibility: true,
      child: LayoutBuilder(
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
    );
  }
}
