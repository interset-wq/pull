import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:flutter_highlight/themes/github.dart';
import 'package:gal/gal.dart';
import 'package:markdown/markdown.dart' as m;
import 'package:markdown_widget/markdown_widget.dart';
import 'package:mermaid_flutter/mermaid_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:scroll_to_index/scroll_to_index.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../git/repo_meta.dart';
import '../notes/details_syntax.dart';
import '../notes/gfm_alerts.dart';
import '../notes/ipynb.dart';
import '../notes/math_render.dart';
import '../notes/note_scanner.dart';
import '../utils/markdown_plain_text.dart';
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
  /// 代码保护段：围栏代码块（``` / ~~~，允许未闭合）与行内代码（单反引号）。
  /// 匹配到的段落内不做任何 HTML 归一化，标签原样显示。
  static final RegExp _codeProtectedRegExp = RegExp(
    r'```[\s\S]*?(?:```|$)|~~~[\s\S]*?(?:~~~|$)|`[^`\n]*`',
  );

  static String normalizeHtmlImages(String md) {
    final out = StringBuffer();
    var cursor = 0;
    for (final m in _codeProtectedRegExp.allMatches(md)) {
      out
        ..write(_normalizeHtmlImagesPlain(md.substring(cursor, m.start)))
        ..write(m.group(0)!);
      cursor = m.end;
    }
    out.write(_normalizeHtmlImagesPlain(md.substring(cursor)));
    return out.toString();
  }

  /// 普通文本段的 HTML 归一化（调用前已剥离代码保护段）。
  static String _normalizeHtmlImagesPlain(String md) {
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
    return _convertHtmlTags(stripped);
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
  // 表格档位（按表存储）：key = 表格在文档中的序号（解析顺序，重建稳定），
  // value = 是否换行档。缺省 = 跟随设置页默认（wideTable 开 → 平铺；关 →
  // 测量驱动自动切档：该表自然宽度 > 2 倍屏宽时单独切为换行档）。
  // 用户点过某表的右上角按钮后，该表不再自动切档。
  final Map<int, bool> _tableWrapOverrides = {};
  int _tableSeq = 0;
  int _detailsSeq = 0;

  /// 表格 [index] 当前生效的换行档。
  bool _tableWraps(int index) =>
      _tableWrapOverrides[index] ?? !(AppPrefs.instance?.wideTable ?? false);
  late Future<String> _content;
  final _scrollController = AutoScrollController();

  /// 当前所在章节（TOC 高亮），-1 表示尚未定位。
  final _currentSection = ValueNotifier<int>(-1);
  final List<GlobalKey> _headingKeys = [];
  final GlobalKey _viewportKey = GlobalKey();

  /// 长图导出的重绘边界（Roadmap「导出与分享·导出长图」）：包裹正文内容
  /// （面包屑 + 渲染结果，不含文末导航）。正文为非懒加载 Column，一次
  /// 布局整篇，边界离屏图层即完整长文，滚动位置不影响截取。
  final GlobalKey _bodyCaptureKey = GlobalKey();
  bool _exportingImage = false;

  /// 导出长图期间的强制展开信号（Roadmap「导出与分享·导出长图」）：
  /// 截图截的是当前视图状态，折叠代码/折叠块若保持收起，长图里就是缺失的；
  /// 置 true 让所有折叠区临时展开，截图完成后复位（用户手动展开的不受影响）。
  final ValueNotifier<bool> _forceExpand = ValueNotifier(false);
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
    // 音量键翻页：全局 handler，页面销毁即注销，其他页面不受影响
    HardwareKeyboard.instance.addHandler(_handleVolumeKey);
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
    HardwareKeyboard.instance.removeHandler(_handleVolumeKey);
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _currentSection.dispose();
    _progressNotifier.dispose();
    _forceExpand.dispose();
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
                case 'copy':
                  _copyFullText();
                case 'copyText':
                  _copyPlainText();
                case 'exportImage':
                  _exportLongImage();
                case 'shareCard':
                  _exportShareCard();
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'raw',
                child: Text(_showRaw ? '渲染视图' : 'Raw 模式'),
              ),
              const PopupMenuItem(value: 'font', child: Text('字号')),
              const PopupMenuItem(
                value: 'copy',
                child: Text('复制全文（Markdown）'),
              ),
              const PopupMenuItem(
                value: 'copyText',
                child: Text('复制全文（纯文本）'),
              ),
              // raw 模式下没有渲染内容，长图/卡片无从生成
              if (!_showRaw) ...[
                const PopupMenuItem(
                  value: 'exportImage',
                  child: Text('导出长图'),
                ),
                const PopupMenuItem(value: 'shareCard', child: Text('分享卡片')),
              ],
            ],
          ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 长图导出进行中：FAB 位显示进度（生成整篇 PNG 可能需要一两秒）
          if (_exportingImage) ...[
            const FloatingActionButton.small(
              heroTag: 'exporting',
              tooltip: '正在生成图片',
              onPressed: null,
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
            const SizedBox(height: 8),
          ],
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
              // 加载失败（文件损坏/ipynb JSON 无效等）明确提示，
              // 不能落到 !hasData 分支永远转圈
              if (snapshot.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      '加载失败：${snapshot.error}',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final fontSize = _fontSizes[_fontIndex];
              final isDark = theme.brightness == Brightness.dark;
              final config = _markdownConfig(theme, isDark, fontSize);
              return _renderBody(snapshot.data!, theme, config);
            },
          ),
      bottomNavigationBar: _buildFooterNav(theme),
    );
  }

  /// 复制整篇 Markdown 源码到剪贴板（Roadmap「导出与分享·复制全文」）。
  Future<void> _copyFullText() async {
    final raw = _rawSource;
    if (raw == null || raw.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('内容尚未加载完成')));
      return;
    }
    await Clipboard.setData(ClipboardData(text: raw));
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已复制全文（Markdown）')));
    }
  }

  /// 复制整篇为纯文本（Roadmap「导出与分享·复制纯文本」）：
  /// GFM AST 提取正文，剥掉 Markdown 语法标记，直接可粘贴到聊天工具。
  Future<void> _copyPlainText() async {
    final raw = _rawSource;
    if (raw == null || raw.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('内容尚未加载完成')));
      return;
    }
    await Clipboard.setData(
      ClipboardData(text: markdownToPlainText(raw)),
    );
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已复制全文（纯文本）')));
    }
  }

  /// 导出长图（Roadmap「导出与分享·导出长图」）：整篇正文截取为一张 PNG
  /// 并调起系统分享（微信/QQ 等直接选会话发送）。正文为非懒加载 Column，
  /// RepaintBoundary 离屏图层即完整内容，与滚动位置无关。
  ///
  /// 截图截的是当前视图状态：导出前先置位强制展开信号（折叠代码/折叠块
  /// 全部展开），两帧稳定后截图，完成后复位——用户手动展开的状态不受影响。
  /// 产物同时存入系统相册「PullRead」（保存失败不阻断分享）。
  Future<void> _exportLongImage() async {
    if (_exportingImage) return;
    final boundary = _bodyCaptureKey.currentContext?.findRenderObject();
    if (boundary is! RenderRepaintBoundary) return;
    setState(() => _exportingImage = true);
    final messenger = ScaffoldMessenger.of(context);
    // dpr 在首个 await 前采集：避免跨 async gap 使用 context
    final dpr = MediaQuery.of(context).devicePixelRatio;
    ui.Image? image;
    try {
      // 强制展开全部折叠区，等两帧让重排（含表格/mermaid 重测量）完成：
      // 第一帧应用展开，第二帧确保整体布局落定，再取最终高度
      _forceExpand.value = true;
      await WidgetsBinding.instance.endOfFrame;
      await WidgetsBinding.instance.endOfFrame;
      // GPU 纹理高度上限（保守值）：超高长图先预降采样，否则 toImage
      // 直接失败或产出被裁剪的坏图
      const maxTexture = 16384.0;
      final target = boundary.size.height * dpr;
      var ratio = target > maxTexture ? dpr * maxTexture / target : dpr;
      for (var attempt = 0; attempt < 4; attempt++) {
        try {
          final img = await boundary.toImage(pixelRatio: ratio);
          final want = (boundary.size.height * ratio).round();
          if ((img.height - want).abs() <= 2) {
            image = img;
            break;
          }
          // 极端设备上 toImage 不抛异常但按上限裁剪：高度不符即重来
          img.dispose();
        } on Object {
          // 纹理超限：降采样重试
        }
        ratio /= 2;
      }
      if (image == null) {
        throw Exception('内容过长，已降到最低清晰度仍无法生成');
      }
      ByteData? bytes;
      try {
        bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      } finally {
        image.dispose();
      }
      if (bytes == null) throw Exception('PNG 编码失败');
      // 尽快还原视图状态，再走保存/分享的慢 IO
      _forceExpand.value = false;
      await WidgetsBinding.instance.endOfFrame;
      await _savePngAndShare(
        bytes.buffer.asUint8List(),
        messenger,
        name: 'pullread-${DateTime.now().millisecondsSinceEpoch}',
      );
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('导出失败：$e')));
    } finally {
      // 兜底还原：任何提前 return/异常路径都不得把页面留在强制展开态
      _forceExpand.value = false;
      if (mounted) setState(() => _exportingImage = false);
    }
  }

  /// PNG 产物落地共用尾段（长图/分享卡片共用）：存入系统相册「PullRead」
  /// （gal 自动按 PNG 推导扩展名；保存失败如拒绝权限只提示，不阻断分享），
  /// 再写临时文件调起系统分享，分享面板拉起后延迟清理临时文件。
  Future<void> _savePngAndShare(
    Uint8List png,
    ScaffoldMessengerState messenger, {
    required String name,
  }) async {
    var savedToGallery = false;
    var galleryDenied = false;
    try {
      if (!await Gal.hasAccess(toAlbum: true)) {
        await Gal.requestAccess(toAlbum: true);
      }
      if (await Gal.hasAccess(toAlbum: true)) {
        await Gal.putImageBytes(png, album: 'PullRead', name: name);
        savedToGallery = true;
      } else {
        galleryDenied = true;
      }
    } on GalException {
      galleryDenied = true;
    }
    if (savedToGallery) {
      messenger.showSnackBar(
        const SnackBar(content: Text('已保存到相册「PullRead」')),
      );
    } else if (galleryDenied) {
      messenger.showSnackBar(
        const SnackBar(content: Text('未获得相册权限，仅生成分享文件')),
      );
    }
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$name.png');
    await file.writeAsBytes(png, flush: true);
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path)], text: _title),
    );
    // 分享面板拉起后临时文件即可清理（延迟留给慢加载的接收方）
    Future<void>.delayed(const Duration(minutes: 5), () {
      try {
        if (file.existsSync()) file.deleteSync();
      } on Object {
        // 清理失败无碍
      }
    });
  }

  /// 分享卡片（Roadmap「导出与分享·分享卡片」）：标题 + 首段摘要 + 来源仓库
  /// 的 4:5 竖版卡片图。不走 RepaintBoundary 截屏，Canvas + TextPainter 离屏
  /// 绘制：固定尺寸无纹理上限问题，也不受折叠区/滚动状态影响。
  /// 配色跟随亮暗主题（表面色 + 松绿品牌点缀），与长图共用存相册+分享尾段。
  Future<void> _exportShareCard() async {
    if (_exportingImage) return;
    setState(() => _exportingImage = true);
    final messenger = ScaffoldMessenger.of(context);
    // dpr 在首个 await 前采集：避免跨 async gap 使用 context
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final theme = Theme.of(context);
    final raw = _rawSource;
    try {
      if (raw == null || raw.isEmpty) {
        throw Exception('内容尚未加载完成');
      }
      final png = await _renderShareCard(
        title: _title ?? widget.note.fileName,
        summary: firstParagraphOfMarkdown(raw),
        source: RepoMeta.read(widget.repoRoot)?.source ??
            widget.repoRoot.split(Platform.pathSeparator).last,
        date: _cardDate(DateTime.now()),
        scheme: theme.colorScheme,
        textTheme: theme.textTheme,
        dpr: dpr,
      );
      await _savePngAndShare(
        png,
        messenger,
        name: 'pullread-card-${DateTime.now().millisecondsSinceEpoch}',
      );
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('卡片生成失败：$e')));
    } finally {
      if (mounted) setState(() => _exportingImage = false);
    }
  }

  /// 卡片日期行：2026-10-27 形式，来源行用
  static String _cardDate(DateTime t) =>
      '${t.year}-${t.month.toString().padLeft(2, '0')}-'
      '${t.day.toString().padLeft(2, '0')}';

  /// 离屏绘制分享卡片。860×1075 逻辑像素（4:5），按 dpr 放大保证清晰度。
  /// 纯 Canvas/TextPainter 同步布局，卡片尺寸小、开销可忽略。
  static Future<Uint8List> _renderShareCard({
    required String title,
    required String summary,
    required String source,
    required String date,
    required ColorScheme scheme,
    required TextTheme textTheme,
    required double dpr,
  }) async {
    const w = 860.0;
    const h = 1075.0;
    const pad = 72.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.scale(dpr);

    // 配色跟随亮暗主题：表面底色 + onSurface 标题 + onSurfaceVariant 摘要，
    // 品牌点缀用 primary（Colors.teal 种子色派生的松绿）
    final fg = scheme.onSurface;
    final sub = scheme.onSurfaceVariant;
    final brand = scheme.primary;
    canvas.drawRect(
      Offset.zero & const Size(w, h),
      ui.Paint()..color = scheme.surface,
    );

    // 只布局不绘制：由调用处决定落笔位置
    TextPainter layout(
      String text, {
      required double fontSize,
      required Color color,
      FontWeight weight = FontWeight.w400,
      double height = 1.4,
      int maxLines = 1,
    }) {
      return TextPainter(
        text: TextSpan(
          text: text,
          style: textTheme.bodyMedium!.copyWith(
            fontSize: fontSize,
            color: color,
            fontWeight: weight,
            height: height,
          ),
        ),
        maxLines: maxLines,
        ellipsis: '…',
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: w - pad * 2);
    }

    // 顶部品牌字
    final brandTp = layout(
      'PullRead 拉读',
      fontSize: 28,
      color: brand,
      weight: FontWeight.w600,
    );
    brandTp.paint(canvas, Offset(pad, pad));

    // 品牌条 + 标题
    var y = pad + brandTp.height + 64;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(pad, y, 56, 10),
        const Radius.circular(5),
      ),
      ui.Paint()..color = brand,
    );
    y += 38;
    final titleTp = layout(
      title,
      fontSize: 56,
      color: fg,
      weight: FontWeight.w700,
      height: 1.3,
      maxLines: 4,
    );
    titleTp.paint(canvas, Offset(pad, y));
    y += titleTp.height + 36;

    // 首段摘要（可缺：纯代码/列表文档没有 <p> 段落）
    if (summary.isNotEmpty) {
      final summaryTp = layout(
        summary,
        fontSize: 32,
        color: sub,
        height: 1.6,
        maxLines: 5,
      );
      summaryTp.paint(canvas, Offset(pad, y));
    }

    // 底部：细分隔线 + 来源行（锚定到底边）
    final lineY = h - pad - 76;
    canvas.drawRect(
      Rect.fromLTWH(pad, lineY, w - pad * 2, 1),
      ui.Paint()..color = scheme.outlineVariant,
    );
    final sourceTp = layout('$source · $date', fontSize: 26, color: sub);
    sourceTp.paint(canvas, Offset(pad, lineY + 32));

    final picture = recorder.endRecording();
    final image = picture.toImageSync((w * dpr).round(), (h * dpr).round());
    picture.dispose();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return bytes!.buffer.asUint8List();
  }

  /// 手势翻页（Roadmap「阅读操作手感」）：正文区域左右快速滑动切换
  /// 上一篇/下一篇。代码块/表格内部的横向滚动视图在手势竞技场中优先，
  /// 横滑它们不会误触翻页；慢速拖动（<500px/s）也不触发。
  void _openSiblingByDrag(DragEndDetails details) {
    final v = details.primaryVelocity ?? 0;
    if (v.abs() < 500) return;
    if (v < 0) {
      _openNextSibling();
    } else {
      _openPrevSibling();
    }
  }

  void _openPrevSibling() {
    if (_siblings.isEmpty || _siblingIndex <= 0) return;
    _openSibling(_siblings[_siblingIndex - 1]);
  }

  void _openNextSibling() {
    if (_siblings.isEmpty ||
        _siblingIndex < 0 ||
        _siblingIndex >= _siblings.length - 1) {
      return;
    }
    _openSibling(_siblings[_siblingIndex + 1]);
  }

  /// 音量键翻页（Roadmap「阅读操作手感」）：阅读页内音量上/下键滚动一屏，
  /// 返回 handled 阻止系统调整音量。非本页按键一律放行。
  bool _handleVolumeKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    final key = event.logicalKey;
    final up = key == LogicalKeyboardKey.audioVolumeUp;
    final down = key == LogicalKeyboardKey.audioVolumeDown;
    if (!up && !down) return false;
    if (!_scrollController.hasClients) return false;
    final pos = _scrollController.position;
    final target = (pos.pixels + (down ? 1 : -1) * pos.viewportDimension * 0.9)
        .clamp(0.0, pos.maxScrollExtent);
    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
    return true;
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

  /// 测量驱动的表格自动切档（按表）：固有列宽首帧渲染后，该表溢出超过
  /// 视口宽（即自然宽度 > 2 倍屏宽）时单独切换为换行档。
  /// 仅在跟随设置默认时生效——wideTable 开关开启或该表已被手动指定档位
  /// （点过其右上角按钮）都不再自动切换。
  void _onTableOverflow(double overflow, int index) {
    if (!mounted || _tableWrapOverrides.containsKey(index)) return;
    if (AppPrefs.instance?.wideTable ?? false) return;
    final viewport = MediaQuery.of(context).size.width;
    if (overflow > viewport) {
      setState(() => _tableWrapOverrides[index] = true);
    }
  }

  /// 切换单个表格的档位（其右上角悬浮按钮）。
  void _toggleTableMode(int index) {
    setState(() => _tableWrapOverrides[index] = !_tableWraps(index));
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
            height: AppPrefs.instance?.lineHeight ?? 1.75,
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
                  height: AppPrefs.instance?.lineHeight ?? 1.75,
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
          // 列宽与宽度外壳不在此设置：自定义的 _PerTableNode 节点按表
          // 独立决定（换行档固定 2 倍屏宽 + FlexColumnWidth 均分列宽，
          // 平铺档固有列宽 + 横向滚动），见 _PerTableNode。
          border: TableBorder.all(
            color: theme.colorScheme.outlineVariant,
            width: 1,
            borderRadius: BorderRadius.circular(6),
          ),
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
    // 表格序号在本次渲染的解析过程中递增分配；每次构建归零，保证同一
    // 文档的表格在重建间拿到稳定索引（_tableWrapOverrides 的 key）。
    _tableSeq = 0;
    _detailsSeq = 0;
    final generator = MarkdownGenerator(
      inlineSyntaxList: [MathInlineSyntax(), MathBlockSyntax()],
      // markdown 包把 <details> 当原始 HTML 文本（不产出元素），自定义
      // 块级语法必须注入，否则 details 生成器永远不会被调用
      blockSyntaxList: [DetailsBlockSyntax()],
      generators: [
        SpanNodeGeneratorWithTag(
          tag: 'table',
          // 覆盖包默认 TableNode：按表独立决定列宽档位与宽度外壳
          generator: (element, config, visitor) {
            final index = _tableSeq++;
            return _PerTableNode(
              config,
              index: index,
              wraps: () => _tableWraps(index),
              onOverflow: (overflow) => _onTableOverflow(overflow, index),
              onToggle: () => _toggleTableMode(index),
            );
          },
        ),
        SpanNodeGeneratorWithTag(
          tag: 'details',
          // GFM 折叠块：可点击标题 + 递归渲染内部 Markdown。
          // 展开初始值：open 属性优先，否则跟随「折叠块默认展开」设置
          //（页面打开时读取，与其余设置开关一致）
          generator: (element, config, visitor) {
            final isOpen = element.attributes['open'] != null;
            return _DetailsNode(
              element,
              index: _detailsSeq++,
              initiallyExpanded:
                  isOpen || (AppPrefs.instance?.detailsExpanded ?? true),
              forceExpand: _forceExpand,
            );
          },
        ),
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
    // 文末导航不进长图：放在重绘边界之外，导出图只含正文内容
    final tail = <Widget>[
      const Divider(height: 32),
      _buildEndNav(theme),
      const SizedBox(height: 90),
    ];
    return GestureDetector(
      // 手势翻页默认关闭（设置页可开）：横滑易与代码块/表格的横向滚动混淆
      onHorizontalDragEnd:
          (AppPrefs.instance?.swipePaging ?? false) ? _openSiblingByDrag : null,
      child: Scrollbar(
        key: _viewportKey,
        controller: _scrollController,
        thumbVisibility: true,
        thickness: 4,
        radius: const Radius.circular(4),
        child: SingleChildScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 长图导出边界：垫底页面背景色（避免透明 PNG 在聊天工具里
              // 显示异常），整篇内容一次布局在边界内
              RepaintBoundary(
                key: _bodyCaptureKey,
                child: ColoredBox(
                  color: theme.scaffoldBackgroundColor,
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: AppPrefs.instance?.pageMargin ?? 16,
                    ),
                    // 大屏行宽限制（Roadmap「阅读操作手感」）：平板/横屏/
                    // 桌面窗口下正文限宽居中，不拉满全屏；窄屏下不起作用
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 860),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: children,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: AppPrefs.instance?.pageMargin ?? 16,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 860),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: tail,
                    ),
                  ),
                ),
              ),
            ],
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
        if (language.toLowerCase() == 'mermaid') {
          return _MermaidBlockView(
            code: code.trimRight(),
            highlightTheme: highlightTheme,
          );
        }
        return _CodeBlockView(
          code: code.trimRight(),
          language: language,
          theme: highlightTheme,
          lineNumbers: prefs?.codeLineNumbers ?? true,
          foldEnabled: prefs?.codeFoldEnabled ?? true,
          foldThreshold: prefs?.codeFoldThreshold ?? 30,
          forceExpand: _forceExpand,
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
    required this.forceExpand,
  });

  final String code;
  final String language;
  final Map<String, TextStyle> theme;
  final bool lineNumbers;
  final bool foldEnabled;
  final int foldThreshold;

  /// 导出长图期间的强制展开信号（宿主页持有）
  final ValueListenable<bool> forceExpand;

  @override
  State<_CodeBlockView> createState() => _CodeBlockViewState();
}

class _CodeBlockViewState extends State<_CodeBlockView> {
  bool _expanded = false;

  TextStyle get _codeStyle => currentCodeFontStyle().copyWith(
        fontSize: 13,
        height: 1.5,
      );

  // highlight 包无 TSX/JSX 语法（未知语言静默回退纯文本），
  // 解析时映射到最近似语法；标签仍显示原语言名
  static const _langAlias = {
    'tsx': 'typescript',
    'jsx': 'javascript',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final parseLang = _langAlias[widget.language] ?? widget.language;
    return LayoutBuilder(
      builder: (context, constraints) {
        // 真无界语境（表格内嵌等）：退化为纯高亮文本，收缩布局不崩
        if (!constraints.maxWidth.isFinite) {
          return HighlightView(
            widget.code,
            language: parseLang,
            theme: widget.theme,
            padding: const EdgeInsets.only(top: 28, left: 12, right: 12, bottom: 4),
            textStyle: _codeStyle,
          );
        }
        final lines = widget.code.split('\n');
        final total = lines.length;
        final foldable = widget.foldEnabled && total > widget.foldThreshold;
        final label = widget.language.isNotEmpty ? widget.language : 'text';
        // 代码区背景 = 高亮主题 root 背景（github #f8f8f8 / atomOneDark #282c34）。
        // 行号列必须用同一颜色：页面 surface 色与之不同，会在左侧形成竖条，
        // 和右上语言标签行拼成"7"形色差
        final codeBg = widget.theme['root']?.backgroundColor ??
            theme.colorScheme.surface;
        // 强制展开信号（导出长图）与用户点按共用一次重建；折叠判定放
        // 监听内部，信号翻转即重建出展开后的完整内容
        return ValueListenableBuilder<bool>(
          valueListenable: widget.forceExpand,
          builder: (context, forceExpand, _) {
          final expanded = _expanded || forceExpand;
          final folded = foldable && !expanded;
          final visibleCode = folded
              ? lines.take(widget.foldThreshold).join('\n')
              : widget.code;
          final gutterLines = folded ? widget.foldThreshold : total;
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
                    language: parseLang,
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
                      // 不透明底色且与代码区同色：横滚时代码会滚到行号列
                      // 下方，透明或异色 gutter 会让代码透出、并形成"7"形色差
                      color: codeBg,
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
                  top: 0,
                  right: 0,
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
                        expanded
                            ? Icons.keyboard_arrow_up
                            : Icons.keyboard_arrow_down,
                        size: 16,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        expanded ? '收起' : '展开全部 $total 行',
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

/// ```mermaid 围栏块：mermaid_flutter 原生渲染（纯 Dart 自绘，无 WebView）。
/// 外观对齐代码块：左上语言标签 + 右上复制源码按钮；超宽图 FittedBox
/// 缩放到屏宽；点按进全屏 MermaidView（pan/zoom/复位）。解析失败由
/// errorBuilder 回退为高亮源码（最坏情况 = 原代码块展示）。
class _MermaidBlockView extends StatelessWidget {
  const _MermaidBlockView({
    required this.code,
    required this.highlightTheme,
  });

  final String code;
  final Map<String, TextStyle> highlightTheme;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mermaidTheme = MaterialMermaidTheme.fromTheme(theme);
    final codeStyle = currentCodeFontStyle().copyWith(fontSize: 13, height: 1.5);
    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 24, left: 12, right: 12, bottom: 8),
          // 正文是 SingleChildScrollView（非懒加载），滚动帧会重记录整页
          // 绘制命令；图表是几百条 Path/Text 的手绘场景，不加边界缓存时
          // 每个滚动帧都重跑 paint，明显卡顿。RepaintBoundary 让引擎把
          // 绘制结果缓存为图层，滚动只做合成偏移。
          child: RepaintBoundary(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _openMermaidFullscreen(context, code),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.topLeft,
                child: MermaidDiagram(
                  source: code,
                  theme: mermaidTheme,
                  errorBuilder: (context, error) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '图表解析失败：$error',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                        const SizedBox(height: 4),
                        HighlightView(
                          code,
                          language: 'mermaid',
                          theme: highlightTheme,
                          textStyle: codeStyle,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          top: 4,
          left: 12,
          child: Text(
            'mermaid',
            style: currentCodeFontStyle().copyWith(
              fontSize: 11,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Positioned(
          top: 0,
          right: 0,
          child: CopyButton(code: code),
        ),
      ],
    );
  }
}

/// mermaid 全屏查看：MermaidView 自带 pan/zoom/复位/全屏对话框。
void _openMermaidFullscreen(BuildContext context, String code) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (context) => Scaffold(
        appBar: AppBar(title: const Text('图表')),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: MermaidView(
              source: code,
              theme: MaterialMermaidTheme.fromTheme(Theme.of(context)),
            ),
          ),
        ),
      ),
    ),
  );
}

/// 按表独立的表格节点：复制包内 TableNode.build 的组装逻辑，但列宽档位
/// 与宽度外壳由宿主按表决定——换行档固定 2 倍屏宽 + FlexColumnWidth 均
/// 分列宽（单元格强制换行），平铺档固有列宽 + 横向滚动（v0.1.0 行为）。
/// 依赖 markdown_widget 内部类（THeadNode/TBodyNode），升级包时需同步。
class _PerTableNode extends ElementNode {
  _PerTableNode(
    this._mdConfig, {
    required this.index,
    required this.wraps,
    required this.onOverflow,
    required this.onToggle,
  });

  final MarkdownConfig _mdConfig;
  final int index;
  final bool Function() wraps;
  final ValueChanged<double> onOverflow;
  final VoidCallback onToggle;

  @override
  InlineSpan build() {
    // 与包内 TableNode.build 一致：表头行 + 表体行组装
    final rows = <TableRow>[];
    var cellCount = 0;
    for (final child in children) {
      if (child is THeadNode) {
        cellCount = child.cellCount;
        rows.addAll(child.rows);
      } else if (child is TBodyNode) {
        rows.addAll(child.buildRows(cellCount));
      }
    }
    final table = Table(
      columnWidths: _mdConfig.table.columnWidths,
      defaultColumnWidth:
          wraps() ? const FlexColumnWidth(1) : const IntrinsicColumnWidth(),
      textBaseline: _mdConfig.table.textBaseline,
      border: _mdConfig.table.border ??
          TableBorder.all(
              color: parentStyle?.color ??
                  _mdConfig.p.textStyle.color ??
                  Colors.grey),
      defaultVerticalAlignment: _mdConfig.table.defaultVerticalAlignment ??
          TableCellVerticalAlignment.middle,
      children: rows,
    );
    return WidgetSpan(
      child: _MarkdownTableHost(
        wraps: wraps(),
        onOverflow: onOverflow,
        onToggle: onToggle,
        child: table,
      ),
    );
  }

  @override
  TextStyle? get style => parentStyle;
}

/// 单个表格的宽度外壳与右上角档位切换按钮（无状态，状态在宿主页的
/// _tableWrapOverrides；点击回调触发宿主 setState 重建）。
class _MarkdownTableHost extends StatelessWidget {
  const _MarkdownTableHost({
    required this.wraps,
    required this.onOverflow,
    required this.onToggle,
    required this.child,
  });

  final bool wraps;
  final ValueChanged<double> onOverflow;
  final VoidCallback onToggle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final core = wraps
        ? LayoutBuilder(
            builder: (context, constraints) => HScrollbar(
              bottomPadding: 6,
              child: SizedBox(
                width: constraints.maxWidth * 2,
                child: child,
              ),
            ),
          )
        : HScrollbar(
            bottomPadding: 6,
            onOverflow: onOverflow,
            child: child,
          );
    return Stack(
      children: [
        core,
        Positioned(
          top: 0,
          right: 0,
          child: IconButton(
            tooltip: wraps ? '该表切换为平铺（不换行）' : '该表切换为换行（限两倍屏宽）',
            icon: const Icon(Icons.swap_horiz),
            iconSize: 16,
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.all(6),
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            onPressed: onToggle,
          ),
        ),
      ],
    );
  }
}

/// GFM 折叠块（&lt;details&gt;/&lt;summary&gt;）节点：标题可点击展开/收起，
/// 内容按块级子节点递归渲染（内部代码块/表格/列表仍按正常样式显示）。
/// 展开状态在 _DetailsBlockHost 的 State 中（稳定 ValueKey 保持元素身份，
/// 文档重建不重置）；初始值由 open 属性或「折叠块默认展开」设置决定。
class _DetailsNode extends ElementNode {
  _DetailsNode(
    this._element, {
    required this.index,
    required this.initiallyExpanded,
    required this.forceExpand,
  });

  final m.Element _element;
  final int index;
  final bool initiallyExpanded;

  /// 导出长图期间的强制展开信号（宿主页持有）
  final ValueListenable<bool> forceExpand;

  /// summary 按 HTML 规范必须是第一个子元素。
  bool get _hasSummary => _element.children
          ?.any((c) => c is m.Element && c.tag == 'summary') ??
      false;

  String get _summaryText {
    for (final c in _element.children ?? const <m.Node>[]) {
      if (c is m.Element && c.tag == 'summary') {
        return c.textContent;
      }
    }
    return '';
  }

  @override
  InlineSpan build() {
    // 子节点顺序与元素子元素一致：有 summary 时跳过首节点（已渲染进标题）
    final content =
        _hasSummary ? children.skip(1).toList() : List.of(children);
    return WidgetSpan(
      child: _DetailsBlockHost(
        key: ValueKey('details-$index'),
        summary: _summaryText,
        initiallyExpanded: initiallyExpanded,
        forceExpand: forceExpand,
        contentNodes: content,
      ),
    );
  }

  @override
  TextStyle? get style => parentStyle;
}

/// 折叠块外壳（有状态组件：展开状态在自身 State，稳定 ValueKey 保证
/// 元素身份，点击只重建本组件）。
class _DetailsBlockHost extends StatefulWidget {
  const _DetailsBlockHost({
    super.key,
    required this.summary,
    required this.initiallyExpanded,
    required this.forceExpand,
    required this.contentNodes,
  });

  final String summary;
  final bool initiallyExpanded;

  /// 导出长图期间的强制展开信号（宿主页持有）
  final ValueListenable<bool> forceExpand;
  final List<SpanNode> contentNodes;

  @override
  State<_DetailsBlockHost> createState() => _DetailsBlockHostState();
}

class _DetailsBlockHostState extends State<_DetailsBlockHost> {
  late bool _expanded = widget.initiallyExpanded;

  // 导出长图强制展开：信号翻转即整体重建（还原由宿主复位信号触发）；
  // 展示状态 = 用户展开或强制展开期间
  bool get _shown => _expanded || widget.forceExpand.value;

  @override
  void initState() {
    super.initState();
    widget.forceExpand.addListener(_refreshOnForceExpand);
  }

  void _refreshOnForceExpand() => setState(() {});

  @override
  void dispose() {
    widget.forceExpand.removeListener(_refreshOnForceExpand);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withAlpha(70),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Icon(
                    _shown ? Icons.expand_more : Icons.chevron_right,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.summary.isEmpty ? '（折叠内容）' : widget.summary,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_shown)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < widget.contentNodes.length; i++) ...[
                    if (i > 0) const SizedBox(height: 8),
                    RichText(
                      text: widget.contentNodes[i].build(),
                      textScaler: MediaQuery.textScalerOf(context),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}
