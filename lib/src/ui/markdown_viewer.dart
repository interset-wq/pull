import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:flutter_highlight/themes/github.dart';
import 'package:markdown_widget/markdown_widget.dart';
import 'package:scroll_to_index/scroll_to_index.dart';
import 'package:url_launcher/url_launcher.dart';

import '../git/repo_meta.dart';
import '../notes/gfm_alerts.dart';
import '../notes/ipynb.dart';
import '../notes/math_render.dart';
import '../notes/note_scanner.dart';
import '../notes/toc.dart';
import '../theme/app_prefs.dart';
import 'code_viewer.dart';
import 'copy_button.dart';
import 'code_font.dart';
import 'h_scrollbar.dart';
import 'home_page.dart';
import 'image_gallery.dart';
import 'repo_image.dart';

/// 笔记阅读页：Markdown 渲染 + 代码高亮 + 相对路径图片。
/// 移动端优先：舒适边距、字号调节、顶栏菜单。
class MarkdownViewerPage extends StatefulWidget {
  const MarkdownViewerPage({
    required this.note,
    required this.repoRoot,
    super.key,
  });

  final NoteFile note;
  final String repoRoot;

  /// 匹配 <img src="...">（属性顺序任意、单双引号均可、含尾部其余属性）。
  static final RegExp _htmlImgRegExp = RegExp(
    r'''<img[^>]*\ssrc=["']([^"']+)["'][^>]*>''',
    caseSensitive: false,
  );

  /// [![alt](img)](link) 徽章式链接图片展平为纯图片。
  static final RegExp _badgeLinkImgRegExp = RegExp(
    r'\[!\[([^\]]*)\]\(([^)\s]+)\)\]\(([^)]+)\)',
  );

  /// SVG 徽章类图片直接忽略：非常用位图格式、难以排版
  /// （shields.io / contrib.rocks / star-history / .svg 文件）。
  static final RegExp _ignoredImageRegExp = RegExp(
    r'!\[[^\]]*\]\((?:[^)]*\.svg(?:\?[^)]*)?'
    r'|https?://img\.shields\.io/[^)]*'
    r'|https?://contrib\.rocks/[^)]*'
    r'|https?://api\.star-history\.com/[^)]*)\)',
    caseSensitive: false,
  );

  /// <div><img src="x"/></div> 等 HTML 内嵌图片转 Markdown 图片语法，
  /// 徽章链接展平为纯图片，同时归一化 <br> 与块级 div/p/a 包裹。
  static String normalizeHtmlImages(String md) {
    final stripped = md
        .replaceAllMapped(
          _htmlImgRegExp,
          (m) => '\n\n![](${m.group(1)!})\n\n',
        )
        .replaceAllMapped(
          _badgeLinkImgRegExp,
          (m) => '![${m.group(1)!}](${m.group(2)!})',
        )
        // 无 src 的空 img 标签（<img> / <img />）与其余 img 残壳直接移除
        .replaceAll(RegExp(r'<img\b[^>]*>', caseSensitive: false), '')
        .replaceAll(RegExp(r'</?a\b[^>]*>', caseSensitive: false), '')
        .replaceAll(RegExp(r'</?div[^>]*>', caseSensitive: false), '')
        .replaceAll(RegExp(r'</?picture[^>]*>', caseSensitive: false), '')
        .replaceAll(RegExp(r'<source\b[^>]*/?>', caseSensitive: false), '')
        .replaceAll(RegExp(r'</?center[^>]*>', caseSensitive: false), '')
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n\n')
        .replaceAll(RegExp(r'</?p\b[^>]*>', caseSensitive: false), '\n\n')
        // 徽章/SVG 图片在排版中无意义，直接忽略
        .replaceAll(_ignoredImageRegExp, '');
    // 行内/块级样式标签转 Markdown 等价语法：按代码围栏切分，
    // 围栏内原样保留，仅转换围栏外的文本
    const fence = r'```[\s\S]*?(?:```|$)|~~~[\s\S]*?(?:~~~|$)';
    final out = StringBuffer();
    var cursor = 0;
    for (final m in RegExp(fence).allMatches(stripped)) {
      out
        ..write(_convertHtmlTags(stripped.substring(cursor, m.start)))
        ..write(m.group(0)!);
      cursor = m.end;
    }
    out.write(_convertHtmlTags(stripped.substring(cursor)));
    return out.toString();
  }

  /// HTML 标签转 Markdown：
  /// 块级 h1-h6 → `#` 标题；strong/b→加粗、em/i→斜体、del/s/strike→删除线；
  /// u/mark/kbd/sub/sup/small/span/font 等无等价语法的剥壳保留文字。
  static String _convertHtmlTags(String md) {
    var text = md;
    // 块级标题：<h1>标题</h1> → # 标题（多行内容取首行）
    text = text.replaceAllMapped(
      RegExp(
        r'<h([1-6])\b[^>]*>([\s\S]*?)</h\1\s*>',
        caseSensitive: false,
      ),
      (m) {
        final level = int.parse(m.group(1)!);
        final inner =
            m.group(2)!.replaceAll(RegExp(r'<[^>]+>'), '').trim();
        return '\n\n${'#' * level} $inner\n\n';
      },
    );
    return text
        .replaceAllMapped(
          RegExp(r'<(strong|b)\b[^>]*>([\s\S]*?)</\1\s*>',
              caseSensitive: false),
          (m) => '**${m.group(2)!}**',
        )
        .replaceAllMapped(
          RegExp(r'<(em|i)\b[^>]*>([\s\S]*?)</\1\s*>', caseSensitive: false),
          (m) => '*${m.group(2)!}*',
        )
        .replaceAllMapped(
          RegExp(r'<(del|s|strike)\b[^>]*>([\s\S]*?)</\1\s*>',
              caseSensitive: false),
          (m) => '~~${m.group(2)!}~~',
        )
        .replaceAll(
          RegExp(
            r'</?(u|mark|kbd|sub|sup|small|span|font)\b[^>]*>',
            caseSensitive: false,
          ),
          '',
        );
  }

  /// 收集文档中按顺序出现的图片地址（Markdown 图片语法）。
  static List<String> collectImageUrls(String body) => RegExp(
        r'!\[[^\]]*\]\(([^)\s]+)\)',
      )
          .allMatches(body)
          .map((m) => m.group(1)!)
          .toList();

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

  /// 当前所在章节（TOC 高亮），-1 表示尚未定位。
  final _currentSection = ValueNotifier<int>(-1);
  final List<GlobalKey> _headingKeys = [];
  final GlobalKey _viewportKey = GlobalKey();
  DateTime _lastSectionUpdate = DateTime.fromMillisecondsSinceEpoch(0);

  /// 回顶/回底浮动按钮显隐（滚动超过一屏后出现）。
  bool _showJump = false;

  /// 同目录下的文章列表（供上一篇/下一篇切换），按文件名排序。
  List<NoteFile> _siblings = const [];
  int _siblingIndex = -1;

  /// 计算同目录文章列表与当前位置（供 上一篇/下一篇）。
  void _loadSiblings() {
    final rel = widget.note.relativePath.replaceAll('\\', '/');
    final dirPart = rel.contains('/') ? rel.substring(0, rel.lastIndexOf('/') + 1) : '';
    final siblings = NoteScanner()
        .scan(widget.repoRoot)
        .where((n) => n.relativePath.replaceAll('\\', '/').startsWith(dirPart))
        .where((n) => !n.relativePath
            .replaceAll('\\', '/')
            .substring(dirPart.length)
            .contains('/'))
        .toList()
      ..sort((a, b) => compareNatural(a.fileName, b.fileName));
    _siblings = siblings;
    _siblingIndex = siblings.indexWhere((n) => n.relativePath == rel);
  }

  @override
  void initState() {
    super.initState();
    _content = _load();
    _starred = RepoMeta.isStarred(widget.repoRoot, widget.note.relativePath);
    _scrollController.addListener(_onScroll);
    AppPrefs.loadFontIndex().then((i) {
      if (mounted && i >= 0 && i < _fontSizes.length) {
        setState(() => _fontIndex = i);
      }
    });
  }

  bool _starred = false;
  // 进度恢复只做一次（内容构建完成后）；保存按滚动节流
  bool _restorePending = true;
  DateTime _lastProgressSave = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _currentSection.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    // 回顶/回底按钮：滚过一屏内容后出现
    final show = _scrollController.offset > 400;
    if (show != _showJump) {
      setState(() => _showJump = show);
    }
    // 章节定位节流：避免每次滚动帧都遍历标题
    final now = DateTime.now();
    if (now.difference(_lastSectionUpdate) >= const Duration(milliseconds: 120)) {
      _lastSectionUpdate = now;
      _updateCurrentSection();
    }
    // 进度：恢复一次；之后按 800ms 节流保存比例位置
    final max = _scrollController.position.maxScrollExtent;
    if (_restorePending) {
      _restorePending = false;
      final saved = RepoMeta.readProgress(
        widget.repoRoot,
        widget.note.relativePath,
      );
      if (saved != null && saved > 0.005 && max > 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.jumpTo(saved * _scrollController.position.maxScrollExtent);
          }
        });
      }
      return;
    }
    if (max > 0 &&
        now.difference(_lastProgressSave) >= const Duration(milliseconds: 800)) {
      _lastProgressSave = now;
      RepoMeta.saveProgress(
        widget.repoRoot,
        widget.note.relativePath,
        (_scrollController.offset / max).clamp(0.0, 1.0),
      );
    }
  }

  /// 当前章节 = 最后一个已进入视口顶部的标题。
  void _updateCurrentSection() {
    if (_headingKeys.isEmpty || !_scrollController.hasClients) return;
    final viewport = _viewportKey.currentContext?.findRenderObject();
    var current = -1;
    for (var i = 0; i < _headingKeys.length; i++) {
      final ro = _headingKeys[i].currentContext?.findRenderObject();
      if (ro is! RenderBox) continue;
      final dy = viewport is! RenderBox
          ? double.infinity
          : ro.localToGlobal(Offset.zero, ancestor: viewport).dy;
      if (dy <= 120) {
        current = i;
      }
    }
    if (current != _currentSection.value) {
      _currentSection.value = current;
    }
  }

  Future<String> _load() async {
    var raw = await File(widget.note.absolutePath).readAsString();
    _rawSource = raw;
    RepoMeta.touchLastOpened(widget.repoRoot, widget.note.relativePath);
    RepoMeta.pushRecent(widget.repoRoot, widget.note.relativePath);
    var body = raw;
    if (widget.note.absolutePath.toLowerCase().endsWith('.ipynb')) {
      body = IpynbConverter.toMarkdown(raw);
    } else {
      final fm = FrontMatter.parse(raw);
      _title = fm.title;
      _tags = fm.tags;
      body = fm.body;
    }
    body = MarkdownViewerPage.normalizeHtmlImages(body);
    _toc = extractToc(body);
    _loadSiblings();
    _headingKeys
      ..clear()
      ..addAll(List.generate(_toc.length, (_) => GlobalKey()));
    _imageUrls = MarkdownViewerPage.collectImageUrls(body);
    return body;
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
          IconButton(
            tooltip: _starred ? '取消收藏' : '收藏',
            icon: Icon(
              _starred ? Icons.star_rounded : Icons.star_outline_rounded,
              color: _starred ? const Color(0xFFF5B301) : null,
            ),
            onPressed: () {
              setState(() {
                _starred = RepoMeta.toggleStar(
                  widget.repoRoot,
                  widget.note.relativePath,
                );
              });
            },
          ),
          if (_tags.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                _tags.join(' · '),
                style: theme.textTheme.bodySmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            tooltip: '更多',
            onSelected: (v) {
              switch (v) {
                case 'raw':
                  setState(() => _showRaw = !_showRaw);
                case 'font':
                  _showFontSheet();
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'raw',
                child: Text(_showRaw ? '渲染视图' : 'Raw 模式'),
              ),
              const PopupMenuItem(value: 'font', child: Text('字号')),
            ],
          ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.small(
            heroTag: 'toc',
            tooltip: '目录',
            onPressed: _showTocSheet,
            child: const Icon(Icons.article_outlined),
          ),
          if (_showJump) ...[
            const SizedBox(height: 8),
            FloatingActionButton.small(
              heroTag: 'jump-top',
              tooltip: '回到顶部',
              onPressed: _scrollToTop,
              child: const Icon(Icons.keyboard_arrow_up),
            ),
            const SizedBox(height: 8),
            FloatingActionButton.small(
              heroTag: 'jump-bottom',
              tooltip: '跳到文末',
              onPressed: _scrollToBottom,
              child: const Icon(Icons.keyboard_arrow_down),
            ),
          ],
        ],
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
              return _renderBody(snapshot.data!, theme, config);
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
        _H3Config(
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
          onTap: _onLinkTap,
        ),
        BlockquoteConfig(
          sideColor: isDark
              ? theme.colorScheme.outline
              : const Color(0xffd0d7de),
          textColor: theme.colorScheme.onSurfaceVariant,
        ),
        CodeConfig(
          style: currentCodeFontStyle().copyWith(
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
          // 注意：不要设置 headerStyle——包内 TBodyNode 也读取 headerStyle
          // （bodyStyle 未被使用），设置加粗表头会让全表变粗体；
          // 不设置时包内默认即"表头加粗、正文正常"。
          border: TableBorder.all(
            color: theme.colorScheme.outlineVariant,
            width: 1,
            borderRadius: BorderRadius.circular(6),
          ),
          wrapper: (child) => HScrollbar(bottomPadding: 6, child: child),
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
      inlineSyntaxList: [MathInlineSyntax(), MathBlockSyntax()],
      generators: [
        SpanNodeGeneratorWithTag(
          tag: 'math',
          generator: (element, config, visitor) =>
              MathNode(element.textContent),
        ),
        SpanNodeGeneratorWithTag(
          tag: 'mathblock',
          generator: (element, config, visitor) => MathNode(
            element.textContent,
            display: true,
          ),
        ),
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
            // _headingKeys 按 extractToc 的 ATX 标题数生成；markdown_widget
            // 还会识别 setext（===/--- 下划线）等形式，计数可能更多，
            // 越界时跳过锚点挂载，避免 RangeError
            if (idx >= 0 &&
                idx < widgets.length &&
                anchorIndex < _headingKeys.length) {
              widgets[idx] = AutoScrollTag(
                key: ValueKey('toc-$anchorIndex'),
                index: anchorIndex,
                controller: _scrollController,
                child: _HeadingMarker(
                  key: _headingKeys[anchorIndex],
                  child: widgets[idx],
                ),
              );
            }
            anchorIndex++;
          }
          children.addAll(widgets);
        case AlertSegment(:final type, :final body):
          children.add(_alertBox(type, body, theme, config, generator));
      }
    }
    if (_siblings.length > 1 && _siblingIndex >= 0) {
      children.addAll([
        const Divider(height: 40),
        _PrevNextNav(
          siblings: _siblings,
          index: _siblingIndex,
          onOpen: _openSibling,
        ),
        const SizedBox(height: 16),
      ]);
    }
    // 底部留白：防止浮动按钮（目录/回顶/回底）遮住末尾文字与翻页按钮
    children.add(const SizedBox(height: 120));
    return Scrollbar(
      key: _viewportKey,
      controller: _scrollController,
      thumbVisibility: true,
      thickness: 4,
      radius: const Radius.circular(4),
      child: SingleChildScrollView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ),
        ),
      ),
    );
  }

  /// 同目录内切换文章：替换当前路由，保持返回栈不变。
  void _openSibling(NoteFile note) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute<void>(
        builder: (_) =>
            MarkdownViewerPage(note: note, repoRoot: widget.repoRoot),
      ),
    );
  }

  /// 浮动按钮：回到文首 / 跳到文末。
  void _scrollToTop() {
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
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
            bottomPadding: 6,
            child: Stack(
              children: [
                HighlightView(
                  // markdown 解析出的 content 带尾随换行/空行，
                  // 不裁掉会渲染成大段底部空白
                  code.trimRight(),
                  language: language,
                  theme: highlightTheme,
                  padding: const EdgeInsets.only(
                      top: 28, left: 12, right: 12, bottom: 4),
                  textStyle: currentCodeFontStyle().copyWith(
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
                      style: currentCodeFontStyle().copyWith(
                        fontSize: 11,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                else
                  Positioned(
                    top: 4,
                    left: 12,
                    child: Text(
                      'text',
                      style: currentCodeFontStyle().copyWith(
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

  /// 链接点击：外部链接浏览器打开；#锚点页内跳转；
  /// 相对路径链接解析为仓库内文件（笔记进阅读页，其余进代码查看器）。
  Future<void> _onLinkTap(String href) async {
    final url = href.trim();
    if (url.isEmpty) return;
    if (url.startsWith('http://') || url.startsWith('https://')) {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      return;
    }
    final hash = url.indexOf('#');
    final pathPart = hash < 0 ? url : url.substring(0, hash);
    final anchor = hash < 0 ? null : url.substring(hash + 1);
    if (pathPart.isEmpty) {
      final idx = _headingIndexForAnchor(anchor!);
      if (idx >= 0) {
        _scrollController.scrollToIndex(
          idx,
          duration: const Duration(milliseconds: 300),
        );
      }
      return;
    }
    final decoded = Uri.decodeComponent(pathPart);
    final target = _resolveLocalPath(decoded);
    if (target == null || !target.startsWith(widget.repoRoot)) {
      return;
    }
    if (Directory(target).existsSync()) {
      // 目录链接：优先打开目录内 index.md / README.md，否则进目录浏览页
      for (final entry in const ['index.md', 'README.md']) {
        final f = File('$target${Platform.pathSeparator}$entry');
        if (f.existsSync()) {
          _openLocalFile(f.path);
          return;
        }
      }
      final sub =
          target.substring(widget.repoRoot.length + 1).replaceAll('\\', '/');
      Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => RepoPage(
            repoDir: Directory(widget.repoRoot),
            subPath: sub,
          ),
        ),
      );
      return;
    }
    if (File(target).existsSync()) {
      _openLocalFile(target);
    }
  }

  /// 解析链接目标为仓库内绝对路径：
  /// `note/`、`./note` 相对当前笔记目录；`/note` 相对仓库根；
  /// 支持 `../` 回退与尾部 `/`（目录）。
  String? _resolveLocalPath(String link) {
    final base =
        link.startsWith('/') ? widget.repoRoot : _noteDir;
    final parts = base.split(Platform.pathSeparator).toList();
    for (final seg in link.split('/')) {
      if (seg.isEmpty || seg == '.') continue;
      if (seg == '..') {
        if (parts.length > 1) parts.removeLast();
        continue;
      }
      parts.add(seg);
    }
    return parts.join(Platform.pathSeparator);
  }

  /// 打开仓库内文件：笔记进阅读页，其余进代码/图片查看器。
  void _openLocalFile(String path) {
    final stat = File(path).statSync();
    final note = NoteFile(
      relativePath: path.substring(widget.repoRoot.length + 1),
      absolutePath: path,
      modified: stat.modified,
      sizeBytes: stat.size,
    );
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => note.isMarkdown
            ? MarkdownViewerPage(note: note, repoRoot: widget.repoRoot)
            : CodeViewerPage(path: path, fileName: note.fileName),
      ),
    );
  }

  /// GitHub 风格标题锚点匹配：小写、去特殊字符、空格转连字符（保留 CJK）。
  int _headingIndexForAnchor(String anchor) {
    final a = anchor.toLowerCase();
    for (var i = 0; i < _toc.length; i++) {
      if (_slugify(_toc[i].text) == a) return i;
    }
    return -1;
  }

  static String _slugify(String text) => text
      .toLowerCase()
      .replaceAll(RegExp(r'[^\p{L}\p{N}\s-]'), '')
      .trim()
      .replaceAll(RegExp(r'\s+'), '-');

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
        child: ValueListenableBuilder<int>(
          valueListenable: _currentSection,
          builder: (context, current, _) {
            final theme = Theme.of(context);
            return ListView.builder(
              itemCount: _toc.length,
              itemBuilder: (context, i) {
                final entry = _toc[i];
                final isCurrent = i == current;
                return ListTile(
                  dense: true,
                  selected: isCurrent,
                  selectedTileColor:
                      theme.colorScheme.primary.withAlpha(isCurrent ? 24 : 0),
                  contentPadding: EdgeInsets.only(left: 16.0 * entry.level),
                  title: Text(
                    entry.text,
                    style: TextStyle(
                      fontSize: 15 - (entry.level - 2) * 0.5,
                      fontWeight:
                          entry.level <= 2 || isCurrent
                              ? FontWeight.w600
                              : FontWeight.w400,
                      color: isCurrent ? theme.colorScheme.primary : null,
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
                AppPrefs.saveFontIndex(v!);
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
                style: currentCodeFontStyle().copyWith(
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
          child: Scrollbar(
            thumbVisibility: true,
            thickness: 4,
            radius: const Radius.circular(4),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              child: SelectableText(
                raw,
                style: currentCodeFontStyle().copyWith(
                  fontSize: 13,
                  height: 1.6,
                  color: theme.colorScheme.onSurface,
                ),
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

/// H1/H2/H3：取消包内默认底部分隔线，层级纯靠字号字重区分。
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

class _H3Config extends H3Config {
  const _H3Config({required super.style});

  @override
  HeadingDivider? get divider => null;
}

/// 标题标记：给 markdown_widget 生成的标题挂 GlobalKey，
/// 供“当前章节”定位使用（不影响 AutoScrollTag 的锚点跳转）。
class _HeadingMarker extends StatefulWidget {
  const _HeadingMarker({super.key, required this.child});

  final Widget child;

  @override
  State<_HeadingMarker> createState() => _HeadingMarkerState();
}

class _HeadingMarkerState extends State<_HeadingMarker> {
  @override
  Widget build(BuildContext context) => widget.child;
}

/// 文末导航：同目录内切换上一篇/下一篇。
class _PrevNextNav extends StatelessWidget {
  const _PrevNextNav({
    required this.siblings,
    required this.index,
    required this.onOpen,
  });

  final List<NoteFile> siblings;
  final int index;
  final ValueChanged<NoteFile> onOpen;

  @override
  Widget build(BuildContext context) {
    final prev = index > 0 ? siblings[index - 1] : null;
    final next = index < siblings.length - 1 ? siblings[index + 1] : null;
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: prev == null ? null : () => onOpen(prev),
            icon: const Icon(Icons.chevron_left),
            label: Text(
              prev?.fileName ?? '已是第一篇',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: next == null ? null : () => onOpen(next),
            icon: const Icon(Icons.chevron_right),
            label: Text(
              next?.fileName ?? '已是最后一篇',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ],
    );
  }
}
