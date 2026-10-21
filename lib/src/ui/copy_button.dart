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
    return Material(
      color: Colors.transparent,
      child: Tooltip(
        message: '复制代码',
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: _copy,
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Icon(
              _copied ? Icons.check : Icons.copy_outlined,
              size: 16,
              color: _copied ? Colors.green : Colors.grey,
            ),
          ),
        ),
      ),
    );
  }
}
