import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:flutter_highlight/themes/github.dart';

import '../notes/code_outline.dart';
import '../search/text_search.dart';
import 'code_font.dart';
import 'copy_button.dart';
import 'h_scrollbar.dart';

/// 代码文件只读查看页：语法高亮 + 行号 + 大纲跳转 + 文内查找 + 自动换行。
///
/// 行高固定（字号 13 × 高度 1.5 = 19.5），大纲跳转按「行 × 行高」估算
/// 滚动位置——高亮视图内部不暴露行级锚点，这个近似在等宽字体下足够准。
class CodeViewerPage extends StatefulWidget {
  const CodeViewerPage({required this.path, required this.fileName, super.key});

  final String path;
  final String fileName;

  @override
  State<CodeViewerPage> createState() => _CodeViewerPageState();
}

class _CodeViewerPageState extends State<CodeViewerPage> {
  static const _fontSize = 13.0;
  static const _lineHeightFactor = 1.5;
  static const _lineHeight = _fontSize * _lineHeightFactor;
  static const _topPadding = 16.0;

  late Future<String> _content;
  String? _text;
  List<CodeSymbol> _symbols = const [];
  final _verticalController = ScrollController();
  final _currentLine = ValueNotifier<int>(1);

  /// 自动换行：开启后长行折行显示，行号列隐藏（折行后行号对不齐）。
  bool _wrap = false;

  // ---- 文内查找 ----
  bool _findOpen = false;
  final _findController = TextEditingController();
  String _findQuery = '';
  List<TextMatch> _matches = const [];
  int _findIndex = -1;

  @override
  void initState() {
    super.initState();
    _content = _load();
    _verticalController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _verticalController.removeListener(_onScroll);
    _verticalController.dispose();
    _currentLine.dispose();
    _findController.dispose();
    super.dispose();
  }

  Future<String> _load() async {
    final text = await File(widget.path).readAsString();
    _text = text;
    _symbols = extractCodeOutline(text, _language);
    // 大纲按钮是否可用取决于符号是否解析出来：AppBar 不随 FutureBuilder
    // 一起重建，这里主动刷新一次
    if (mounted) setState(() {});
    return text;
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
    '.vue': 'vue',
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

  void _onScroll() {
    if (!_verticalController.hasClients) return;
    final line =
        ((_verticalController.offset - _topPadding) / _lineHeight).floor() + 1;
    final clamped = line < 1 ? 1 : line;
    if (clamped != _currentLine.value) _currentLine.value = clamped;
  }

  /// 跳到第 [line] 行（1 基）：按固定行高估算偏移。
  void _jumpToLine(int line) {
    if (!_verticalController.hasClients) return;
    final max = _verticalController.position.maxScrollExtent;
    final offset = _topPadding + (line - 1) * _lineHeight;
    _verticalController.animateTo(
      offset.clamp(0.0, max),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  void _showOutline() {
    final symbols = _symbols;
    if (symbols.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('没有识别到可跳转的符号'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.92,
        builder: (sheetContext, scrollController) =>
            ValueListenableBuilder<int>(
          valueListenable: _currentLine,
          builder: (sheetContext, currentLine, _) => ListView.builder(
            controller: scrollController,
            itemCount: symbols.length,
            itemBuilder: (sheetContext, i) {
              final symbol = symbols[i];
              final nextLine =
                  i + 1 < symbols.length ? symbols[i + 1].line : 1 << 30;
              final isCurrent =
                  currentLine >= symbol.line && currentLine < nextLine;
              return ListTile(
                dense: true,
                selected: isCurrent,
                leading: Icon(_iconFor(symbol.kind), size: 18),
                title: Text(
                  symbol.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Text(
                  '${symbol.line}',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _jumpToLine(symbol.line);
                },
              );
            },
          ),
        ),
      ),
    );
  }

  static IconData _iconFor(String kind) => switch (kind) {
        'class' => Icons.category_outlined,
        'section' => Icons.segment,
        _ => Icons.functions,
      };

  // ---- 文内查找 ----

  void _toggleFind() {
    if (_findOpen) {
      _closeFind();
      return;
    }
    setState(() => _findOpen = true);
  }

  void _closeFind() {
    setState(() {
      _findOpen = false;
      _findQuery = '';
      _matches = const [];
      _findIndex = -1;
    });
    _findController.clear();
  }

  void _onFindChanged(String value) {
    final query = value.trim();
    final text = _text ?? '';
    final matches =
        query.isEmpty ? const <TextMatch>[] : findTextMatches(text, query);
    setState(() {
      _findQuery = query;
      _matches = matches;
      _findIndex = matches.isEmpty ? -1 : 0;
    });
    if (matches.isNotEmpty) _jumpToLine(matches.first.line + 1);
  }

  void _stepMatch(int delta) {
    if (_matches.isEmpty) return;
    final next = (_findIndex + delta + _matches.length) % _matches.length;
    setState(() => _findIndex = next);
    _jumpToLine(_matches[next].line + 1);
  }

  Widget _buildFindBar(ThemeData theme) {
    final counter = _matches.isEmpty
        ? (_findQuery.isEmpty ? '' : '无匹配')
        : '${_findIndex + 1}/${_matches.length}';
    return Container(
      color: theme.colorScheme.surfaceContainerHighest.withAlpha(80),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _findController,
              autofocus: true,
              decoration: const InputDecoration(
                isDense: true,
                hintText: '在代码中查找',
                border: InputBorder.none,
              ),
              onChanged: _onFindChanged,
            ),
          ),
          Text(counter, style: theme.textTheme.bodySmall),
          IconButton(
            tooltip: '上一处',
            icon: const Icon(Icons.keyboard_arrow_up),
            onPressed: _matches.isEmpty ? null : () => _stepMatch(-1),
          ),
          IconButton(
            tooltip: '下一处',
            icon: const Icon(Icons.keyboard_arrow_down),
            onPressed: _matches.isEmpty ? null : () => _stepMatch(1),
          ),
          IconButton(
            tooltip: '关闭',
            icon: const Icon(Icons.close),
            onPressed: _closeFind,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.fileName, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: '大纲',
            icon: const Icon(Icons.toc_outlined),
            onPressed: _symbols.isEmpty ? null : _showOutline,
          ),
          IconButton(
            tooltip: _findOpen ? '关闭查找' : '查找',
            icon: Icon(_findOpen ? Icons.search_off : Icons.search),
            onPressed: _toggleFind,
          ),
          IconButton(
            tooltip: _wrap ? '关闭自动换行' : '自动换行',
            icon: Icon(
              Icons.wrap_text,
              color: _wrap ? theme.colorScheme.primary : null,
            ),
            onPressed: () => setState(() => _wrap = !_wrap),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_findOpen) _buildFindBar(theme),
          Expanded(
            child: FutureBuilder<String>(
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
                      color:
                          theme.colorScheme.surfaceContainerHighest.withAlpha(70),
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
                            style: currentCodeFontStyle().copyWith(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            '${lines.length} 行',
                            style: theme.textTheme.bodySmall,
                          ),
                          const Spacer(),
                          CopyButton(code: content),
                        ],
                      ),
                    ),
                    Expanded(
                      // 行号列与代码同处一个垂直滚动视图：天然同步滚动，
                      // 不会出现两个 Scrollable 共享 controller 时行号不跟滚的问题
                      child: Scrollbar(
                        controller: _verticalController,
                        thumbVisibility: true,
                        thickness: 4,
                        radius: const Radius.circular(4),
                        child: SingleChildScrollView(
                          controller: _verticalController,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (!_wrap)
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    12,
                                    _topPadding,
                                    6,
                                    _topPadding,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.end,
                                    children: [
                                      for (var i = 0; i < lines.length; i++)
                                        Text(
                                          '${i + 1}',
                                          style: currentCodeFontStyle().copyWith(
                                            fontSize: _fontSize,
                                            height: _lineHeightFactor,
                                            color: theme.colorScheme.outline,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              Expanded(
                                child: _wrap
                                    ? HighlightView(
                                        content,
                                        language: _language,
                                        theme: isDark
                                            ? atomOneDarkTheme
                                            : githubTheme,
                                        padding: const EdgeInsets.fromLTRB(
                                          12,
                                          _topPadding,
                                          16,
                                          _topPadding,
                                        ),
                                        textStyle:
                                            currentCodeFontStyle().copyWith(
                                          fontSize: _fontSize,
                                          height: _lineHeightFactor,
                                        ),
                                      )
                                    : HScrollbar(
                                        child: HighlightView(
                                          content,
                                          language: _language,
                                          theme: isDark
                                              ? atomOneDarkTheme
                                              : githubTheme,
                                          padding: const EdgeInsets.fromLTRB(
                                            4,
                                            _topPadding,
                                            16,
                                            _topPadding,
                                          ),
                                          textStyle:
                                              currentCodeFontStyle().copyWith(
                                            fontSize: _fontSize,
                                            height: _lineHeightFactor,
                                          ),
                                        ),
                                      ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
