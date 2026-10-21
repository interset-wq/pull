import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:flutter_highlight/themes/github.dart';

import 'code_font.dart';
import 'copy_button.dart';
import 'h_scrollbar.dart';

/// 代码文件只读查看页：语法高亮（对标 GitHub mobile 的代码浏览体验）。
class CodeViewerPage extends StatefulWidget {
  const CodeViewerPage({required this.path, required this.fileName, super.key});

  final String path;
  final String fileName;

  @override
  State<CodeViewerPage> createState() => _CodeViewerPageState();
}

class _CodeViewerPageState extends State<CodeViewerPage> {
  late Future<String> _content;
  final _verticalController = ScrollController();

  @override
  void dispose() {
    _verticalController.dispose();
    super.dispose();
  }

  /// 根据扩展名推断语言（映射到 highlight.js 的语言名）。
  static const _extLanguage = {
    '.dart': 'dart',
    '.py': 'python',
    '.js': 'javascript',
    '.mjs': 'javascript',
    '.ts': 'typescript',
    '.tsx': 'typescript',
    '.jsx': 'javascript',
    '.java': 'java',
    '.kt': 'kotlin',
    '.kts': 'kotlin',
    '.go': 'go',
    '.rs': 'rust',
    '.c': 'c',
    '.h': 'c',
    '.cpp': 'cpp',
    '.cc': 'cpp',
    '.hpp': 'cpp',
    '.cs': 'csharp',
    '.rb': 'ruby',
    '.php': 'php',
    '.swift': 'swift',
    '.m': 'objectivec',
    '.sh': 'bash',
    '.bash': 'bash',
    '.zsh': 'bash',
    '.json': 'json',
    '.yaml': 'yaml',
    '.yml': 'yaml',
    '.toml': 'ini',
    '.xml': 'xml',
    '.html': 'xml',
    '.css': 'css',
    '.scss': 'scss',
    '.sql': 'sql',
    '.r': 'r',
    '.lua': 'lua',
    '.pl': 'perl',
    '.txt': 'plaintext',
  };

  String get _language {
    final dot = widget.fileName.lastIndexOf('.');
    if (dot == -1) return 'plaintext';
    final ext = widget.fileName.substring(dot).toLowerCase();
    return _extLanguage[ext] ?? 'plaintext';
  }

  @override
  void initState() {
    super.initState();
    _content = File(widget.path).readAsString();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.fileName, overflow: TextOverflow.ellipsis),
      ),
      body: FutureBuilder<String>(
        future: _content,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('无法读取文件: ${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final content = snapshot.data!;
          final lines = content.split('\n');
          return Column(
            children: [
              // 文件信息栏：语言、行数、快捷复制
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                color: theme.colorScheme.surfaceContainerHighest.withAlpha(70),
                child: Row(
                  children: [
                    Icon(
                      Icons.code,
                      size: 16,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _language,
                      style: kCodeFontStyle.copyWith(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text('${lines.length} 行', style: theme.textTheme.bodySmall),
                    const Spacer(),
                    CopyButton(code: content),
                  ],
                ),
              ),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 行号列：与代码共用同一垂直滚动控制器保持对齐
                    SingleChildScrollView(
                      controller: _verticalController,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 16, 6, 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            for (var i = 0; i < lines.length; i++)
                              Text(
                                '${i + 1}',
                                style: kCodeFontStyle.copyWith(
                                  fontSize: 13,
                                  height: 1.5,
                                  color: theme.colorScheme.outline,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        controller: _verticalController,
                        child: HScrollbar(
                          child: HighlightView(
                            content,
                            language: _language,
                            theme: isDark ? atomOneDarkTheme : githubTheme,
                            padding: const EdgeInsets.fromLTRB(4, 16, 16, 16),
                            textStyle: kCodeFontStyle.copyWith(
                              fontSize: 13,
                              height: 1.5,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
