import 'dart:io';

import 'package:flutter/material.dart';

import '../notes/note_scanner.dart';

/// 轻量编辑页：多行 Markdown 编辑 + 本地保存。
/// 保存即写入本地文件；提交推送在阅读页/列表页触发。
class NoteEditorPage extends StatefulWidget {
  const NoteEditorPage({required this.note, super.key});

  final NoteFile note;

  @override
  State<NoteEditorPage> createState() => _NoteEditorPageState();
}

class _NoteEditorPageState extends State<NoteEditorPage> {
  late final TextEditingController _ctrl;
  late final Future<String> _content;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _content = File(widget.note.absolutePath).readAsString();
    _content.then((text) => _ctrl = TextEditingController(text: text));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<bool> _confirmDiscard() async {
    if (!_dirty) return true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('放弃修改？'),
        content: const Text('当前内容尚未保存'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('继续编辑'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('放弃'),
          ),
        ],
      ),
    );
    return discard == true;
  }

  Future<void> _save() async {
    await File(widget.note.absolutePath).writeAsString(_ctrl.text, flush: true);
    if (!mounted) return;
    setState(() => _dirty = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已保存到本地，提交推送请在阅读页操作'),
        duration: Duration(seconds: 2),
      ),
    );
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscard() && context.mounted) {
          Navigator.pop(context, _dirty);
        }
      },
      child: FutureBuilder<String>(
        future: _content,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          return Scaffold(
            appBar: AppBar(
              title: Text(
                widget.note.fileName,
                overflow: TextOverflow.ellipsis,
              ),
              actions: [
                IconButton(
                  onPressed: _dirty ? _save : null,
                  icon: const Icon(Icons.save_outlined),
                  tooltip: '保存',
                ),
              ],
            ),
            body: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
              child: TextField(
                controller: _ctrl,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                keyboardType: TextInputType.multiline,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      height: 1.6,
                      fontFamily: 'monospace',
                    ),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  hintText: 'Markdown 内容…',
                ),
                onChanged: (_) => setState(() => _dirty = true),
              ),
            ),
          );
        },
      ),
    );
  }
}
