import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 代码块右上角的复制按钮，点击后短暂变为已复制状态。
class CopyButton extends StatefulWidget {
  const CopyButton({super.key, required this.code});

  final String code;

  @override
  State<CopyButton> createState() => _CopyButtonState();
}

class _CopyButtonState extends State<CopyButton> {
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.code));
    if (!mounted) return;
    setState(() => _copied = true);
    Future<void>.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    // 与表格右上角档位切换按钮同规格：28×28 紧凑 IconButton，
    // 悬浮锚定在容器右上角，不参与内容布局、不受横向滚动影响
    return Material(
      color: Colors.transparent,
      child: IconButton(
        tooltip: _copied ? '已复制' : '复制代码',
        icon: Icon(
          _copied ? Icons.check : Icons.copy_outlined,
          color: _copied ? Colors.green : null,
        ),
        iconSize: 16,
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.all(6),
        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
        onPressed: _copy,
      ),
    );
  }
}
