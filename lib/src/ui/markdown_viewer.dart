import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:flutter_highlight/themes/github.dart';
import 'package:markdown_widget/markdown_widget.dart';
import 'package:scroll_to_index/scroll_to_index.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../git/repo_meta.dart';
import '../notes/gfm_alerts.dart';
import '../notes/ipynb.dart';
import '../notes/math_render.dart';
import '../notes/note_scanner.dart';
import '../notes/table_layout.dart';
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

  /// 剩余阅读时间（分钟，_load 时估算一次）。
  int _readingMinutes = 0;

  /// 最近一次进入视口的标题索引（进度记忆的锚点）。
  int _lastHeadingIndex = -1;

  // ---- 视图状态 ----
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

  /// 滚动进度（0~1），驱动 AppBar 底部的细进度条。
  final ValueNotifier<double> _progressNotifier = ValueNotifier(0);

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
    // 同目录文章列表同步算好：footer 翻页条在 FutureBuilder 之外，
    // 若等 _load 里赋值，没有 setState 触发它重建——pushReplacement
    // 过来的新页面会停在空状态，翻页按钮消失
    _loadSiblings();
    _content = _load();
    _starred = RepoMeta.isStarred(widget.repoRoot, widget.note.relativePath);
    _scrollController.addListener(_onScroll);
    // 屏幕常亮：仅阅读页生效，离开即恢复系统行为
    if (AppPrefs.instance?.keepScreenOn ?? false) {
      WakelockPlus.enable();
    }
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
    WakelockPlus.disable();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _currentSection.dispose();
    _progressNotifier.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    // 顶部细进度条：按滚动比例实时更新
    final maxExtent = _scrollController.position.maxScrollExtent;
    _progressNotifier.value =
        maxExtent > 0 ? (_scrollController.offset / maxExtent).clamp(0.0, 1.0) : 0;
    // 章节定位节流：避免每次滚动帧都遍历标题
    final now = DateTime.now();
    if (now.difference(_lastSectionUpdate) >= const Duration(milliseconds: 120)) {
      _lastSectionUpdate = now;
      _updateCurrentSection();
    }
    // 进度：询问一次是否跳回（不强转）；之后按 800ms 节流保存比例位置
    final max = _scrollController.position.maxScrollExtent;
    if (_restorePending) {
      _restorePending = false;
      final (saved, headingIdx) = RepoMeta.readProgressInfo(
        widget.repoRoot,
        widget.note.relativePath,
      );
      // 有些用户不需要跳回（比如想从头重读），只提示不强跳
      if (saved > 0.005 && max > 0) {
        _offerProgressRestore(saved, headingIdx);
      }
      return;
    }
    if (max > 0 &&
        now.difference(_lastProgressSave) >= const Duration(milliseconds: 800)) {
      _lastProgressSave = now;
      RepoMeta.saveProgressInfo(
        widget.repoRoot,
        widget.note.relativePath,
        (_scrollController.offset / max).clamp(0.0, 1.0),
        _lastHeadingIndex,
      );
    }
  }

  /// 有历史阅读进度时弹模态框询问「是否跳回上次位置」，
  /// 用户选择「从头开始」则从开头读，不再强行跳转。
  void _offerProgressRestore(double saved, int? headingIdx) {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('上次读到此处'),
        content: Text('是否跳转到上次阅读位置（约 ${(saved * 100).round()}%）？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('从头开始'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              if (!mounted || !_scrollController.hasClients) return;
              // 标题锚点优先：字号/窗口变化导致布局高度漂移时，
              // 标题位置不受影响，比纯比例恢复更准
              if (headingIdx != null &&
                  headingIdx >= 0 &&
                  headingIdx < _headingKeys.length &&
                  _headingKeys[headingIdx].currentContext != null) {
                Scrollable.ensureVisible(
                  _headingKeys[headingIdx].currentContext!,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOut,
                );
              } else {
                _scrollController.animateTo(
                  (saved * _scrollController.position.maxScrollExtent)
                      .clamp(0.0, _scrollController.position.maxScrollExtent),
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOut,
                );
              }
            },
            child: const Text('跳到上次位置'),
          ),
        ],
      ),
    );
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
      if (current >= 0) _lastHeadingIndex = current;
    }
  }

  Future<String> _load() async {
    var raw = await File(widget.note.absolutePath).readAsString();
    _rawSource = raw;
    RepoMeta.touchLastOpened(widget.repoRoot, widget.note.relativePath);
    RepoMeta.pushRecent(
      widget.repoRoot,
      widget.note.relativePath,
      limit: AppPrefs.instance?.recentsLimit ?? 5,
    );
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
    _headingKeys
      ..clear()
      ..addAll(List.generate(_toc.length, (_) => GlobalKey()));
    _imageUrls = MarkdownViewerPage.collectImageUrls(body);
    _readingMinutes = _estimateReadingMinutes(body);
    return body;
  }

  /// 估算阅读分钟数：正文按 300 字/分钟，代码块按 200 字符/分钟折算，
  /// 结果保留 1 位小数精度（<1 分钟显示"约 1 分钟"）。
  int _estimateReadingMinutes(String body) {
    var codeChars = 0;
    var textChars = 0;
    var inFence = false;
    for (final line in body.split('\n')) {
      final t = line.trim();
      if (t.startsWith('```') || t.startsWith('~~~')) {
        inFence = !inFence;
        continue;
      }
      if (inFence) {
        codeChars += t.length;
      } else {
        textChars += t.replaceAll(RegExp(r'\s'), '').length;
      }
    }
    final minutes = textChars / 300 + codeChars / 200;
    return minutes < 1 ? 1 : minutes.ceil();
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
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(2),
          child: ValueListenableBuilder<double>(
            valueListenable: _progressNotifier,
            builder: (context, value, _) => _showRaw
                // raw 无阅读进度可言；value:null 的 indeterminate
                // 形态是一条持续动画的横线，看着像在加载
                ? const SizedBox(height: 2)
                : LinearProgressIndicator(value: value, minHeight: 2),
          ),
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
          // raw 模式下没有渲染锚点，不提供目录
          if (!_showRaw) ...[
            FloatingActionButton.small(
              heroTag: 'toc',
              tooltip: '目录',
              onPressed: _showTocSheet,
              child: const Icon(Icons.article_outlined),
            ),
            const SizedBox(height: 8),
          ],
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
              final config = _markdownConfig(theme, isDark, fontSize, snapshot.data!);
              return _renderBody(snapshot.data!, theme, config);
            },
          ),
      bottomNavigationBar: _buildFooterNav(theme),
    );
  }

  /// 跳到仓库内 `subPath` 对应的目录页（'' = 仓库根）。
  /// 面包屑与文末导航按钮共用。
  /// 收藏/最近阅读直达时栈里没有目录页：先退栈到仓库根（没有则在
  /// 首页之上补推一个），再把途中各级目录页依次推入，保证返回栈完整。
  void _openRepoDir(String subPath) {
    var foundRepoRoute = false;
    Navigator.of(context).popUntil((route) {
      if (route.settings.name == 'repo-root') {
        foundRepoRoute = true;
        return true;
      }
      return route.isFirst;
    });
    if (!foundRepoRoute) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => RepoPage(repoDir: Directory(widget.repoRoot)),
          settings: const RouteSettings(name: 'repo-root'),
        ),
      );
    }
    // 逐级推入从仓库根到目标目录之间的路径（subPath 的每一段）
    final target =
        subPath.isEmpty ? const <String>[] : subPath.split('/');
    for (var depth = 1; depth <= target.length; depth++) {
      final path = target.sublist(0, depth).join('/');
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => RepoPage(
            repoDir: Directory(widget.repoRoot),
            subPath: path,
          ),
        ),
      );
    }
  }

  /// 文首面包屑：文件夹图标 + 仓库 / 目录路径，与正文区分。
  /// 仓库与每一级目录都是独立点击目标，跳到各自的目录页；
  /// 根目录文章（无目录层级）不显示。
  Widget _buildBreadcrumb(ThemeData theme) {
    final repoName =
        widget.repoRoot.split(Platform.pathSeparator).last;
    final dirSegments = widget.note.relativePath
        .replaceAll('\\', '/')
        .split('/')
      ..removeLast()
      ..removeWhere((s) => s.isEmpty);
    if (dirSegments.isEmpty) return const SizedBox.shrink();
    final style = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.folder_outlined,
            size: 14,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 4),
          // 仓库根
          Flexible(
            child: InkWell(
              borderRadius: BorderRadius.circular(4),
              onTap: () => _openRepoDir(''),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
                child: Text(repoName, style: style),
              ),
            ),
          ),
          for (var i = 0; i < dirSegments.length; i++) ...[
            Text(' / ', style: style),
            Flexible(
              child: InkWell(
                borderRadius: BorderRadius.circular(4),
                onTap: () =>
                    _openRepoDir(dirSegments.sublist(0, i + 1).join('/')),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 2,
                    vertical: 4,
                  ),
                  child: Text(dirSegments[i], style: style),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 文末导航：回到上级目录 / 回到仓库首页，替代纯留白。
  /// 上级目录跳到父目录页，仓库首页跳到仓库根；共用 _openRepoDir。
  Widget _buildEndNav(ThemeData theme) {
    final repoName =
        widget.repoRoot.split(Platform.pathSeparator).last;
    final dirSegments = widget.note.relativePath
        .replaceAll('\\', '/')
        .split('/')
      ..removeLast()
      ..removeWhere((s) => s.isEmpty);
    final parentPath =
        dirSegments.isEmpty ? '' : dirSegments.join('/');

    Widget button(IconData icon, String label, VoidCallback onTap) =>
        OutlinedButton(
          onPressed: onTap,
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            foregroundColor: theme.colorScheme.onSurfaceVariant,
            side: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
          // 自绘内容并 center：.icon 构造在拉伸宽度时会靠左排布
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        );

    // 外层 _renderBody 的 Column（CrossAxisAlignment.start）给有界宽度，
    // 这里 Center + 3/5 比例才能真正居中限宽（无界宽度下 Center 会收缩）。
    return Center(
      child: FractionallySizedBox(
        widthFactor: 0.6,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            button(
              Icons.arrow_upward,
              dirSegments.isEmpty ? '目录' : dirSegments.last,
              () => _openRepoDir(parentPath),
            ),
            const SizedBox(height: 8),
            button(
              Icons.home_outlined,
              repoName,
              () => _openRepoDir(''),
            ),
          ],
        ),
      ),
    );
  }

  /// 底部常驻翻页条：上一篇/下一篇始终可用，不必滚到文末。
  /// 同目录仅一篇或索引未就绪时不显示。
  Widget _buildFooterNav(ThemeData theme) {
    if (_siblings.isEmpty || _siblingIndex < 0 || _siblings.length < 2) {
      return const SizedBox.shrink();
    }
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border(
            top: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: _PrevNextNav(
          siblings: _siblings,
          index: _siblingIndex,
          onOpen: _openSibling,
        ),
      ),
    );
  }

  MarkdownConfig _markdownConfig(
    ThemeData theme,
    bool isDark,
    double fontSize,
    String body,
  ) {
    // 表格两档渲染：自然宽度 > 2 倍屏宽时按 2 倍屏宽强制换行
    final screenWidth = MediaQuery.of(context).size.width;
    final wrapTables =
        estimateTableNaturalWidth(body, fontSize) > 2 * screenWidth;
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
          // 列宽策略（两档）：表格自然宽度 > 2 倍屏宽时改用
          // FlexColumnWidth 并固定 2 倍屏宽强制换行，否则保留固有列宽
          // + 横向滚动（最多 2 屏宽，滚动距离可控）
          defaultColumnWidth: wrapTables
              ? const FlexColumnWidth()
              : const IntrinsicColumnWidth(),
          border: TableBorder.all(
            color: theme.colorScheme.outlineVariant,
            width: 1,
            borderRadius: BorderRadius.circular(6),
          ),
          wrapper: (child) => wrapTables
              ? LayoutBuilder(
                  builder: (context, constraints) => HScrollbar(
                    bottomPadding: 6,
                    child: SizedBox(
                      width: constraints.maxWidth * 2,
                      child: child,
                    ),
                  ),
                )
              : HScrollbar(bottomPadding: 6, child: child),
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
    final children = <Widget>[
      Row(
        children: [
          Expanded(child: _buildBreadcrumb(theme)),
          if (_readingMinutes > 0) ...[
            const SizedBox(width: 8),
            Icon(
              Icons.schedule_outlined,
              size: 13,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 2),
            Text(
              '约 $_readingMinutes 分钟',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
      const SizedBox(height: 4),
    ];
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
    // 文末导航：回到上级目录 / 仓库首页，替代纯留白
    children
      ..add(const Divider(height: 32))
      ..add(_buildEndNav(theme))
      ..add(const SizedBox(height: 90));
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
    final prefs = AppPrefs.instance;
    return PreConfig(
      padding: EdgeInsets.zero,
      decoration: const BoxDecoration(),
      builder: (code, language) {
        return _CodeBlockView(
          code: code.trimRight(),
          language: language,
          theme: highlightTheme,
          lineNumbers: prefs?.codeLineNumbers ?? true,
          foldEnabled: prefs?.codeFoldEnabled ?? true,
          foldThreshold: prefs?.codeFoldThreshold ?? 30,
        );
      },
    );
  }

  /// Raw 视图文本：整段源码按当前代码字体渲染（无搜索高亮）。
  TextSpan _rawSpans(ThemeData theme) {
    final raw = _rawSource ?? '';
    return TextSpan(
      text: raw,
      style: currentCodeFontStyle().copyWith(
        fontSize: _fontSizes[_fontIndex],
        height: 1.6,
        color: theme.colorScheme.onSurface,
      ),
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
      if (idx >= 0) _jumpToHeadingTop(idx);
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

  /// 跳到第 [index] 个标题并让标题贴住视口顶部（TOC / #锚点共用）。
  /// scrollToIndex 的定位结果常落在屏幕底部；ensureVisible alignment 0
  /// 把标题首行对齐到视口上沿，符合「目录点了去哪儿」的直觉。
  void _jumpToHeadingTop(int index) {
    if (index < 0 || index >= _headingKeys.length) return;
    final ctx = _headingKeys[index].currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      alignment: 0,
    );
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
                    _jumpToHeadingTop(i);
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
            controller: _scrollController,
            child: SingleChildScrollView(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              child: SelectableText.rich(
                _rawSpans(theme),
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
    // markdown 包对链接目的地址做百分号编码（CommonMark 规范），中文
    // 文件名到达此处已是编码串；图库列表/Hero 标签/本地解析都用原始
    // 路径，入口统一解码对齐。
    final src = decodeMarkdownUrl(url.trim());
    final index = _imageUrls.indexOf(src);
    return GestureDetector(
      onTap: () => _openGallery(index < 0 ? 0 : index),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          // 浅色垫底：透明 PNG/SVG 图表按白底设计，深色主题下不可读
          child: Hero(
            tag: 'img-$src',
            child: buildRepoImage(src, baseDir: _noteDir, backdrop: true),
          ),
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
  Widget build(BuildContext context) {
    return widget.child;
  }
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

/// 代码块视图：约束自适应。
/// markdown_widget 把 builder 结果包进 WidgetSpan；正常块级语境下宽度
/// 有界，但代码块若再被包进横向滚动容器（或表格等嵌套语境）就会以
/// 无界宽度布局——Row+Expanded、Column(stretch)、width:double.infinity
/// 在该路径下全部崩溃（C6 案例文件黑屏的根因）。
/// 因此：横滚区里只放收缩安全的 HighlightView；行号列、语言标签、
/// 复制按钮、折叠开关都在有界外层叠加；LayoutBuilder 兜底真无界语境
/// （退化为纯高亮文本）。
class _CodeBlockView extends StatefulWidget {
  const _CodeBlockView({
    required this.code,
    required this.language,
    required this.theme,
    required this.lineNumbers,
    required this.foldEnabled,
    required this.foldThreshold,
  });

  final String code;
  final String language;
  final Map<String, TextStyle> theme;
  final bool lineNumbers;
  final bool foldEnabled;
  final int foldThreshold;

  @override
  State<_CodeBlockView> createState() => _CodeBlockViewState();
}

class _CodeBlockViewState extends State<_CodeBlockView> {
  bool _expanded = false;

  TextStyle get _codeStyle => currentCodeFontStyle().copyWith(
        fontSize: 13,
        height: 1.5,
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        // 真无界语境（表格内嵌等）：退化为纯高亮文本，收缩布局不崩
        if (!constraints.maxWidth.isFinite) {
          return HighlightView(
            widget.code,
            language: widget.language,
            theme: widget.theme,
            padding: const EdgeInsets.only(top: 28, left: 12, right: 12, bottom: 4),
            textStyle: _codeStyle,
          );
        }
        final lines = widget.code.split('\n');
        final total = lines.length;
        final foldable = widget.foldEnabled && total > widget.foldThreshold;
        final folded = foldable && !_expanded;
        final visibleCode =
            folded ? lines.take(widget.foldThreshold).join('\n') : widget.code;
        final gutterLines = folded ? widget.foldThreshold : total;
        final label = widget.language.isNotEmpty ? widget.language : 'text';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Stack(
              children: [
                // 横滚区只放 HighlightView：无界宽度下收缩安全
                HScrollbar(
                  bottomPadding: 6,
                  child: HighlightView(
                    visibleCode,
                    language: widget.language,
                    theme: widget.theme,
                    padding: EdgeInsets.only(
                      top: 28,
                      left: widget.lineNumbers ? 52 : 12,
                      right: 12,
                      bottom: 4,
                    ),
                    textStyle: _codeStyle,
                  ),
                ),
                // 语言标签：固定不随代码横滚
                Positioned(
                  top: 4,
                  left: 12,
                  child: Text(
                    label,
                    style: currentCodeFontStyle().copyWith(
                      fontSize: 11,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                // 行号列：固定不随代码横滚，与代码行同字号同行高对齐
                if (widget.lineNumbers)
                  Positioned(
                    top: 28,
                    left: 0,
                    width: 44,
                    bottom: 4,
                    child: Container(
                      alignment: Alignment.topRight,
                      padding: const EdgeInsets.only(right: 8),
                      // 不透明底色：横滚时代码会滚到行号列下方，
                      // 透明 gutter 会让代码文字透出、和行号混在一起
                      color: theme.colorScheme.surface,
                      // 滚动容器裁剪：吸收缩放语境下与代码行的取整差，
                      // 否则 Column 比外层高 1px 就报 overflow
                      child: SingleChildScrollView(
                        physics: const NeverScrollableScrollPhysics(),
                        child: _LineNumberColumn(
                          lineCount: gutterLines,
                          color:
                              theme.colorScheme.onSurfaceVariant.withAlpha(110),
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  top: 4,
                  right: 4,
                  child: CopyButton(code: widget.code),
                ),
              ],
            ),
            if (foldable)
              InkWell(
                onTap: () => setState(() => _expanded = !_expanded),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _expanded
                            ? Icons.keyboard_arrow_up
                            : Icons.keyboard_arrow_down,
                        size: 16,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _expanded ? '收起' : '展开全部 $total 行',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// 行号列：与代码同字号同行高，保证每行行号与代码行对齐。
class _LineNumberColumn extends StatelessWidget {
  const _LineNumberColumn({required this.lineCount, required this.color});

  final int lineCount;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final style = currentCodeFontStyle().copyWith(
      fontSize: 13,
      height: 1.5,
      color: color,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var i = 1; i <= lineCount; i++)
          Text('$i', style: style, overflow: TextOverflow.clip),
      ],
    );
  }
}
