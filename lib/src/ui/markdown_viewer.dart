import 'dart:io';

import 'package:flutter/material.dart';
import 'package:markdown_widget/markdown_widget.dart';

import '../notes/note_scanner.dart';

/// 笔记阅读页：Markdown 渲染 + 代码高亮 + 相对路径图片。
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
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _title ?? widget.note.fileName,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (_tags.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: Text(
                  _tags.join(' · '),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
        ],
      ),
      body: FutureBuilder<String>(
        future: _content,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return MarkdownWidget(
            data: snapshot.data!,
            config: MarkdownConfig(
              configs: [
                const PreConfig(),
                ImgConfig(builder: (url, alt) => _buildImage(url)),
              ],
            ),
          );
        },
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
      return Image.file(file, errorBuilder: (_, _, _) => _broken(url));
    }
    return _broken(url);
  }

  Widget _broken(String url) => Text('[图片缺失: $url]');
}
