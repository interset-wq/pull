import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:flutter_highlight/themes/github.dart';

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
          return SingleChildScrollView(
            scrollDirection: Axis.vertical,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: HighlightView(
                snapshot.data!,
                language: _language,
                theme: isDark ? atomOneDarkTheme : githubTheme,
                padding: const EdgeInsets.all(16),
                textStyle: const TextStyle(
                  fontSize: 13,
                  fontFamily: 'monospace',
                  height: 1.5,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
