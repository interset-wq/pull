import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:flutter_highlight/themes/github.dart';
import 'package:markdown_widget/markdown_widget.dart';
import 'package:scroll_to_index/scroll_to_index.dart';

import '../notes/gfm_alerts.dart';
import '../notes/ipynb.dart';
import '../notes/note_scanner.dart';
import '../notes/toc.dart';
import 'copy_button.dart';
import 'code_font.dart';
import 'h_scrollbar.dart';
import 'image_gallery.dart';
import 'repo_image.dart';

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
  List<TocEntry> _toc = const [];
  List<String> _imageUrls = const [];
  String? _rawSource;
  bool _showRaw = false;
  late Future<String> _content;
  final _scrollController = AutoScrollController();

  @override
  void initState() {
    super.initState();
    _content = _load();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<String> _load() async {
    var raw = await File(widget.note.absolutePath).readAsString();
    _rawSource = raw;
    var body = raw;
    if (widget.note.absolutePath.toLowerCase().endsWith('.ipynb')) {
      body = IpynbConverter.toMarkdown(raw);
    } else {
      final fm = FrontMatter.parse(raw);
      _title = fm.title;
      _tags = fm.tags;
      body = fm.body;
    }
    body = _normalizeHtmlImages(body);
    _toc = extractToc(body);
    _imageUrls = _collectImageUrls(body);
    return body;
  }

  /// 匹配 <img src="...">（属性顺序任意、单双引号均可）。
  static final RegExp _htmlImgRegExp = RegExp(
    r'''<img[^>]*\ssrc=["']([^"']+)["']''',
    caseSensitive: false,
  );

  /// [![alt](img)](link) 徽章式链接图片展平为纯图片。
  static final RegExp _badgeLinkImgRegExp = RegExp(
    r'\[!\[([^\]]*)\]\(([^)\s]+)\)\]\(([^)]+)\)',
  );

  /// <div><img src="x"/></div> 等 HTML 内嵌图片转 Markdown 图片语法，
  /// 徽章链接展平为纯图片，同时归一化 <br> 与块级 div/p/a 包裹。
  static String _normalizeHtmlImages(String md) {
    return md
        .replaceAllMapped(
          _htmlImgRegExp,
          (m) => '\n\n![](${m.group(1)!})\n\n',
        )
        .replaceAllMapped(
          _badgeLinkImgRegExp,
          (m) => '![${m.group(1)!}](${m.group(2)!})',
        )
        .replaceAll(RegExp(r'</?a\b[^>]*>', caseSensitive: false), '')
        .replaceAll(RegExp(r'</?div[^>]*>', caseSensitive: false), '')
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n\n')
        .replaceAll(RegExp(r'</?p[^>]*>', caseSensitive: false), '\n\n');
  }

  /// 收集文档中按顺序出现的图片地址（Markdown 图片语法）。
  static List<String> _collectImageUrls(String body) => RegExp(
        r'!\[[^\]]*\]\(([^)\s]+)\)',
      )
          .allMatches(body)
          .map((m) => m.group(1)!)
          .toList();

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
              tooltip: '目录',
              onPressed: _showTocSheet,
              icon: const Icon(Icons.list_outlined),
            ),
            IconButton(
              tooltip: _showRaw ? '渲染视图' : 'Raw 模式',
              onPressed: () => setState(() => _showRaw = !_showRaw),
              icon: Icon(_showRaw ? Icons.article_outlined : Icons.data_object),
            ),
            const Spacer(),
            IconButton(
              tooltip: '字号',
              onPressed: _showFontSheet,
              icon: const Icon(Icons.format_size),
            ),
          ],
        ),
      ),
      body: _showRaw
          ? _buildRawView(theme)
          : FutureBuilder<String>(
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
        _H1Config(
          style: theme.textTheme.headlineLarge!.copyWith(
            fontSize: 30,
            height: 1.35,
            fontWeight: FontWeight.w800,
            color: theme.colorScheme.onSurface,
          ),
        ),
        _H2Config(
          style: theme.textTheme.headlineSmall!.copyWith(
            fontSize: 24,
            height: 1.35,
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.onSurface,
          ),
        ),
        H3Config(
          style: theme.textTheme.titleLarge!.copyWith(
            fontSize: 20,
            height: 1.4,
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.onSurface,
          ),
        ),
        H4Config(
          style: theme.textTheme.titleMedium!.copyWith(
            fontSize: 17,
            height: 1.4,
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.onSurface,
          ),
        ),
        PConfig(
          textStyle: theme.textTheme.bodyLarge!.copyWith(
            fontSize: fontSize,
            height: 1.75,
          ),
        ),
        ListConfig(
          marker: (isOrdered, depth, index) {
            if (isOrdered) {
              return Text(
                '${index + 1}.',
                style: TextStyle(
                  color: theme.colorScheme.primary,
                  fontSize: fontSize,
                  height: 1.75,
                  fontWeight: FontWeight.w600,
                ),
              );
            }
            return Container(
              width: (6 - depth).toDouble(),
              height: (6 - depth).toDouble(),
              margin: const EdgeInsets.only(top: 10),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary
                    .withAlpha(255 - depth * 60),
                shape: BoxShape.circle,
              ),
            );
          },
        ),
        CheckBoxConfig(
          builder: (checked) => Icon(
            checked ? Icons.check_box : Icons.check_box_outline_blank,
            size: 20,
            color: theme.colorScheme.primary,
          ),
        ),
        LinkConfig(
          style: theme.textTheme.bodyLarge!.copyWith(
            fontSize: fontSize,
            color: isDark
                ? theme.colorScheme.tertiary
                : const Color(0xff0969da),
            decoration: TextDecoration.underline,
            decorationColor: isDark
                ? theme.colorScheme.tertiary.withAlpha(120)
                : const Color(0xff0969da).withAlpha(80),
          ),
        ),
        BlockquoteConfig(
          sideColor: isDark
              ? theme.colorScheme.outline
              : const Color(0xffd0d7de),
          textColor: theme.colorScheme.onSurfaceVariant,
        ),
        CodeConfig(
          style: kCodeFontStyle.copyWith(
            backgroundColor: isDark
                ? theme.colorScheme.surfaceContainerHighest.withAlpha(204)
                : const Color(0xCCeff1f3),
            color: theme.colorScheme.onSurface,
          ),
        ),
        TableConfig(
          headerRowDecoration: BoxDecoration(
            color: theme.colorScheme.primary.withAlpha(25),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
          ),
          headerStyle: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.onSurface,
          ),
          bodyStyle: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface,
          ),
          border: TableBorder.all(
            color: theme.colorScheme.outlineVariant,
            width: 1,
            borderRadius: BorderRadius.circular(6),
          ),
          wrapper: (child) => HScrollbar(child: child),
        ),
        _preConfig(theme, isDark),
        ImgConfig(builder: (url, alt) => _buildImage(url)),
      ],
    );
  }

  /// 正文渲染：按 GFM 告警块分割，告警渲染为彩色提示框；
  /// 标题挂 AutoScrollTag 供目录锚点跳转（目录列表由 _load 的 extractToc 提供，
  /// 两者均按文档顺序生成，索引一一对应）。
  Widget _renderBody(
    String content,
    ThemeData theme,
    MarkdownConfig config,
  ) {
    final generator = MarkdownGenerator(
      generators: [
        SpanNodeGeneratorWithTag(
          tag: 'blockquote',
          generator: (element, config, visitor) => _CardBlockquoteNode(
            visitor,
            backgroundColor:
                theme.colorScheme.surfaceContainerHighest.withAlpha(70),
            barColor: theme.colorScheme.primary.withAlpha(160),
          ),
        ),
      ],
    );
    final children = <Widget>[];
    var anchorIndex = 0;
    for (final segment in splitGfmAlerts(content)) {
      switch (segment) {
        case TextSegment(:final text):
          List<Toc>? tocs;
          final widgets = generator.buildWidgets(
            text,
            config: config,
            onTocList: (list) => tocs = list,
          );
          final tocList = tocs ?? const <Toc>[];
          for (final toc in tocList) {
            final idx = toc.widgetIndex;
            if (idx >= 0 && idx < widgets.length) {
              widgets[idx] = AutoScrollTag(
                key: ValueKey('toc-$anchorIndex'),
                index: anchorIndex,
                controller: _scrollController,
                child: widgets[idx],
              );
            }
            anchorIndex++;
          }
          children.addAll(widgets);
        case AlertSegment(:final type, :final body):
          children.add(_alertBox(type, body, theme, config, generator));
      }
    }
    return SingleChildScrollView(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
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

  /// 代码块配置：flutter_highlight 语法高亮（跟随主题），右上角一键复制。
  PreConfig _preConfig(ThemeData theme, bool isDark) {
    final highlightTheme = isDark ? atomOneDarkTheme : githubTheme;
    return PreConfig(
      padding: EdgeInsets.zero,
      decoration: const BoxDecoration(),
      builder: (code, language) {
        // 与 HighlightView 的主题背景同色，块元素化占满视口宽度
        final bg = highlightTheme['root']?.backgroundColor;
        return Container(
          width: double.infinity,
          color: bg,
          child: HScrollbar(
            child: Stack(
              children: [
                HighlightView(
                  code,
                  language: language,
                  theme: highlightTheme,
                  padding: const EdgeInsets.only(
                      top: 28, left: 12, right: 12, bottom: 12),
                  textStyle: kCodeFontStyle.copyWith(
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
                if (language.isNotEmpty)
                  Positioned(
                    top: 4,
                    left: 12,
                    child: Text(
                      language,
                      style: kCodeFontStyle.copyWith(
                        fontSize: 11,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                Positioned(
                  top: 4,
                  right: 4,
                  child: CopyButton(code: code),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showTocSheet() {
    if (_toc.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('本文没有标题'),
          duration: Duration(seconds: 1),
        ),
      );
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView.builder(
          itemCount: _toc.length,
          itemBuilder: (context, i) {
            final entry = _toc[i];
            return ListTile(
              dense: true,
              contentPadding: EdgeInsets.only(left: 16.0 * entry.level),
              title: Text(
                entry.text,
                style: TextStyle(
                  fontSize: 15 - (entry.level - 2) * 0.5,
                  fontWeight:
                      entry.level <= 2 ? FontWeight.w600 : FontWeight.w400,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () {
                Navigator.pop(context);
                _scrollController.scrollToIndex(
                  i,
                  duration: const Duration(milliseconds: 300),
                );
              },
            );
          },
        ),
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

  /// Raw 模式：原始 Markdown 全文可选可复制（对标 GitHub mobile）。
  Widget _buildRawView(ThemeData theme) {
    final raw = _rawSource ?? '';
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(
            children: [
              Text(
                'Raw',
                style: kCodeFontStyle.copyWith(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.primary,
                ),
              ),
              const Spacer(),
              CopyButton(code: raw),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            child: SelectableText(
              raw,
              style: kCodeFontStyle.copyWith(
                fontSize: 13,
                height: 1.6,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// markdown 文件所在目录，相对图片的解析基准。
  String get _noteDir => File(widget.note.absolutePath).parent.path;

  /// 正文图片：统一加载（本地/网络），点击进入图片阅读器。
  Widget _buildImage(String url) {
    final src = url.trim();
    final index = _imageUrls.indexOf(src);
    return GestureDetector(
      onTap: () => _openGallery(index < 0 ? 0 : index),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: buildRepoImage(src, baseDir: _noteDir),
        ),
      ),
    );
  }

  void _openGallery(int index) {
    if (_imageUrls.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => ImageGalleryPage(
          sources: _imageUrls,
          baseDir: _noteDir,
          initialIndex: index,
        ),
      ),
    );
  }
}

/// 引用块卡片化：浅背景 + 圆角 + 主题色左条（混合风格）。
class _CardBlockquoteNode extends ElementNode {
  _CardBlockquoteNode(
    this.visitor, {
    required this.backgroundColor,
    required this.barColor,
  });

  final WidgetVisitor visitor;
  final Color backgroundColor;
  final Color barColor;

  @override
  InlineSpan build() {
    return WidgetSpan(
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(8),
          border: Border(
            left: BorderSide(color: barColor, width: 3),
          ),
        ),
        child: ProxyRichText(
          childrenSpan,
          richTextBuilder: visitor.richTextBuilder,
        ),
      ),
    );
  }

  @override
  TextStyle? get style =>
      TextStyle(color: parentStyle?.color).merge(parentStyle);
}

/// H1/H2：取消包内默认底部分隔线，层级纯靠字号字重区分。
class _H1Config extends H1Config {
  const _H1Config({required super.style});

  @override
  HeadingDivider? get divider => null;
}

class _H2Config extends H2Config {
  const _H2Config({required super.style});

  @override
  HeadingDivider? get divider => null;
}
