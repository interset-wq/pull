import 'dart:io';

import 'package:flutter/material.dart';
import 'package:markdown_widget/markdown_widget.dart';

import '../git/sync_service.dart';
import '../notes/gfm_alerts.dart';
import '../notes/note_scanner.dart';
import 'copy_button.dart';
import 'note_editor.dart';

/// 笔记阅读页：Markdown 渲染 + 代码高亮 + 相对路径图片。
/// 移动端优先：舒适边距、字号调节、底部工具栏。
class MarkdownViewerPage extends StatefulWidget {
  const MarkdownViewerPage({
    required this.note,
    required this.repoRoot,
    super.key,
  });

  final NoteFile note;
  final String repoRoot;

  @override
  State<MarkdownViewerPage> createState() => _MarkdownViewerPageState();
}

class _MarkdownViewerPageState extends State<MarkdownViewerPage> {
  static const _fontSizes = [14.0, 16.0, 18.0, 20.0, 24.0];
  int _fontIndex = 1;

  String? _title;
  List<String> _tags = const [];
  late Future<String> _content;

  @override
  void initState() {
    super.initState();
    _content = _load();
  }

  Future<String> _load() async {
    final raw = await File(widget.note.absolutePath).readAsString();
    final fm = FrontMatter.parse(raw);
    _title = fm.title;
    _tags = fm.tags;
    return fm.body;
  }

  Future<void> _edit() async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute<bool>(
        builder: (_) => NoteEditorPage(note: widget.note),
      ),
    );
    if (saved == true) {
      setState(() => _content = _load());
    }
  }

  Future<void> _commitAndPush() async {
    final msgCtrl = TextEditingController(text: 'update ${widget.note.fileName}');
    final tokenCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('提交并推送'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: msgCtrl,
              decoration: const InputDecoration(
                labelText: '提交说明',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: tokenCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: '访问 Token',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('提交推送'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final pushed = await GitSyncService().commitAndPush(
        repoDir: Directory(widget.repoRoot),
        paths: [widget.note.relativePath],
        message: msgCtrl.text.trim(),
        userName: 'reader',
        userEmail: 'reader@local',
        token: tokenCtrl.text.trim(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(pushed ? '已提交并推送' : '没有需要提交的改动'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } on Exception catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('提交失败: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _title ?? widget.note.fileName,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (_tags.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Text(
                  _tags.join(' · '),
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: BottomAppBar(
        height: 48,
        child: Row(
          children: [
            IconButton(
              tooltip: '编辑',
              onPressed: _edit,
              icon: const Icon(Icons.edit_outlined),
            ),
            const Spacer(),
            IconButton(
              tooltip: '提交推送',
              onPressed: _commitAndPush,
              icon: const Icon(Icons.cloud_upload_outlined),
            ),
            IconButton(
              tooltip: '字号',
              onPressed: _showFontSheet,
              icon: const Icon(Icons.format_size),
            ),
          ],
        ),
      ),
      body: FutureBuilder<String>(
        future: _content,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final fontSize = _fontSizes[_fontIndex];
          final isDark = theme.brightness == Brightness.dark;
          final config = _markdownConfig(theme, isDark, fontSize);
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _renderBody(snapshot.data!, theme, config),
          );
        },
      ),
    );
  }

  MarkdownConfig _markdownConfig(
    ThemeData theme,
    bool isDark,
    double fontSize,
  ) {
    return MarkdownConfig(
      configs: [
        H1Config(style: theme.textTheme.headlineMedium!.copyWith(height: 1.4)),
        H2Config(style: theme.textTheme.headlineSmall!.copyWith(height: 1.4)),
        H3Config(style: theme.textTheme.titleLarge!.copyWith(height: 1.4)),
        PConfig(
          textStyle: theme.textTheme.bodyLarge!.copyWith(
            fontSize: fontSize,
            height: 1.75,
          ),
        ),
        const ListConfig(),
        _preConfig(theme, isDark),
        ImgConfig(builder: (url, alt) => _buildImage(url)),
      ],
    );
  }

  /// 正文渲染：按 GFM 告警块分割，告警渲染为彩色提示框。
  Widget _renderBody(
    String content,
    ThemeData theme,
    MarkdownConfig config,
  ) {
    final generator = MarkdownGenerator();
    final children = <Widget>[];
    for (final segment in splitGfmAlerts(content)) {
      switch (segment) {
        case TextSegment(:final text):
          children.addAll(generator.buildWidgets(text, config: config));
        case AlertSegment(:final type, :final body):
          children.add(_alertBox(type, body, theme, config, generator));
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  /// GFM 告警框：左侧色条 + 图标标题 + 正文。
  Widget _alertBox(
    GfmAlertType type,
    String body,
    ThemeData theme,
    MarkdownConfig config,
    MarkdownGenerator generator,
  ) {
    final color = Color(type.color);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(color: color, width: 4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_alertIcon(type), size: 16, color: color),
              const SizedBox(width: 6),
              Text(
                type.title,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          ...generator.buildWidgets(body, config: config),
        ],
      ),
    );
  }

  IconData _alertIcon(GfmAlertType type) => switch (type) {
        GfmAlertType.note => Icons.info_outline,
        GfmAlertType.tip => Icons.lightbulb_outline,
        GfmAlertType.important => Icons.priority_high_outlined,
        GfmAlertType.warning => Icons.warning_amber_outlined,
        GfmAlertType.caution => Icons.dangerous_outlined,
      };

  /// 代码块配置：配色跟随全局明暗主题，右上角一键复制。
  PreConfig _preConfig(ThemeData theme, bool isDark) {
    final codeBg = isDark
        ? theme.colorScheme.surfaceContainerHighest
        : const Color(0xffeff1f3);
    return PreConfig(
      decoration: BoxDecoration(
        color: codeBg,
        borderRadius: const BorderRadius.all(Radius.circular(8)),
      ),
      textStyle: TextStyle(
        fontSize: 14,
        color: theme.colorScheme.onSurface,
      ),
      wrapper: (child, code, language) => Stack(
        children: [
          child,
          Positioned(
            top: 4,
            right: 4,
            child: CopyButton(code: code),
          ),
        ],
      ),
    );
  }

  void _showFontSheet() {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('字号'),
            ),
            RadioGroup<int>(
              groupValue: _fontIndex,
              onChanged: (v) {
                setState(() => _fontIndex = v!);
                Navigator.pop(context);
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < _fontSizes.length; i++)
                    RadioListTile<int>(
                      value: i,
                      title: Text(_fontSizes[i].toStringAsFixed(0)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 仓库内相对路径的图片解析为本地文件；网络图片原样加载。
  Widget _buildImage(String url) {
    final clean = url.trim();
    if (clean.startsWith('http://') || clean.startsWith('https://')) {
      return Image.network(clean);
    }
    final file = File(
      '${widget.repoRoot}${Platform.pathSeparator}'
      '${clean.replaceAll('/', Platform.pathSeparator)}',
    );
    if (file.existsSync()) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.file(file, errorBuilder: (_, _, _) => _broken(url)),
        ),
      );
    }
    return _broken(url);
  }

  Widget _broken(String url) => Text('[图片缺失: $url]');
}
