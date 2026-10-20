import 'dart:io';

import 'package:flutter/material.dart';
import 'package:markdown_widget/markdown_widget.dart';

import '../notes/note_scanner.dart';

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
    _content = () async {
      final raw = await File(widget.note.absolutePath).readAsString();
      final fm = FrontMatter.parse(raw);
      _title = fm.title;
      _tags = fm.tags;
      return fm.body;
    }();
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
            const Spacer(),
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
          return MarkdownWidget(
            data: snapshot.data!,
            config: MarkdownConfig(
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
                const PreConfig(),
                ImgConfig(builder: (url, alt) => _buildImage(url)),
              ],
            ),
          );
        },
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
