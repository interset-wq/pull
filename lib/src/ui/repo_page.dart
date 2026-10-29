import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../git/repo_meta.dart';
import '../git/sync_service.dart';
import '../local/local_folder_service.dart';
import '../notes/link_check.dart';
import '../notes/note_index.dart';
import '../notes/note_scanner.dart';
import '../platforms/git_platform.dart';
import '../platforms/repo_info.dart';
import '../search/repo_search.dart';
import '../search/text_search.dart';
import '../theme/app_prefs.dart';
import 'open_note.dart';
import 'pull_progress.dart';
import 'search_snippet_text.dart';
class RepoPage extends StatefulWidget {
  const RepoPage({required this.repoDir, this.subPath = '', super.key});

  final Directory repoDir;

  /// 相对仓库根的当前目录（'' = 根目录）。
  final String subPath;

  @override
  State<RepoPage> createState() => _RepoPageState();
}

class _RepoPageState extends State<RepoPage> {
  late final NoteScanner _scanner = () {
    final prefs = AppPrefs.instance;
    return NoteScanner(
      useDefaults: prefs?.ignoreDefaults ?? true,
      customRules: prefs?.ignoreRules ?? const [],
    );
  }();
  List<NoteFile>? _allNotes;
  String _query = '';
  bool _scanning = false;
  int _scanSeq = 0;

  /// 上次 pull 之后新增/修改且尚未打开过的文件（path → 'a'/'m'）。
  Map<String, String> _recentChanges = const {};

  /// 阅读进度（相对路径 → 0~1），仓库页展示「读到 N% / 已读完」。
  Map<String, double> _progress = const {};

  /// 仅显示没有阅读记录的文件（有进度就算读过）。
  bool _unreadOnly = false;

  /// 文件行尾部的「新增/更新」标记（pull 后未打开过的文件）。
  Widget? _recentChangeBadge(String relativePath, ThemeData theme) {
    final kind = _recentChanges[relativePath];
    if (kind == null) return null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withAlpha(30),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        kind == 'a' ? '新增' : '更新',
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }

  /// 打开文件时清除它的更新标记（阅读过即不再提示）。
  void _markOpened(NoteFile note) {
    if (!_recentChanges.containsKey(note.relativePath)) return;
    RepoMeta.clearRecentChange(widget.repoDir.path, note.relativePath);
    setState(() {
      _recentChanges = Map.of(_recentChanges)..remove(note.relativePath);
    });
  }

  /// 文件行尾部：更新角标 + 阅读状态。
  /// 未读不单独标注（否则每行都是「未读」），用「仅看未读」筛选表达。
  Widget? _fileTrailing(NoteFile note, ThemeData theme) {
    final badge = _recentChangeBadge(note.relativePath, theme);
    final progress = _progress[note.relativePath];
    String? label;
    if (progress != null && progress > 0.005) {
      label = progress >= 0.98
          ? '已读完'
          : '读到 ${(progress * 100).round()}%';
    }
    if (badge == null && label == null) return null;
    final children = <Widget>[];
    if (badge != null) children.add(badge);
    if (label != null) {
      if (badge != null) children.add(const SizedBox(width: 6));
      children.add(
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return Row(mainAxisSize: MainAxisSize.min, children: children);
  }

  // 正文搜索（全文）：文件名搜索是同步过滤，正文搜索走后台 isolate + 防抖
  bool _contentMode = false;
  Timer? _searchDebounce;
  List<FileSearchResult>? _contentResults;
  bool _contentSearching = false;
  int _contentSeq = 0;

  /// 断链检查进行中（只读检查，不修改仓库）。
  bool _linkChecking = false;

  /// 文件排序：按名称（自然序，默认）或按修改时间（新的在前）。
  bool _sortByModified = false;

  // 就地展开的目录（相对仓库根路径集合），会话内保持；默认全部折叠
  final Set<String> _expandedDirs = <String>{};

  Directory get _currentDir => Directory(
      '${widget.repoDir.path}${Platform.pathSeparator}'
      '${widget.subPath.replaceAll('/', Platform.pathSeparator)}'
          .replaceAll(RegExp(r'[/\\]+$'), ''));

  @override
  void initState() {
    super.initState();
    // 先用磁盘缓存渲染首帧（大仓库不必等递归扫描），后台再重扫校正
    _allNotes = NoteIndexCache.read(widget.repoDir.path);
    _loadRecentChanges();
    _progress = RepoMeta.readAllProgress(widget.repoDir.path);
    _scanNotes();
  }

  /// 上次 pull 之后新增/修改且尚未打开过的文件（path → 'a'/'m'）。
  void _loadRecentChanges() {
    setState(() {
      _recentChanges = RepoMeta.readRecentChanges(widget.repoDir.path);
    });
  }

  Future<void> _refresh() => _scanNotes();

  /// 后台 isolate 扫描：UI 线程不做递归 listSync；更新的扫描会顶掉旧结果。
  Future<void> _scanNotes() async {
    final seq = ++_scanSeq;
    if (mounted) setState(() => _scanning = true);
    try {
      final files = await scanNotesInBackground(
        widget.repoDir.path,
        useDefaults: _scanner.useDefaults,
        customRules: _scanner.customRules,
      );
      if (!mounted || seq != _scanSeq) return;
      setState(() => _allNotes = files);
      await NoteIndexCache.write(widget.repoDir.path, files);
    } on Object {
      // 扫描失败保留缓存/旧列表，不打断阅读
    } finally {
      if (mounted && seq == _scanSeq) setState(() => _scanning = false);
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }

  /// 搜索框输入：文件名模式同步过滤；正文模式防抖后跑后台检索。
  void _onQueryChanged(String value) {
    final q = value.toLowerCase();
    setState(() {
      _query = q;
      _contentResults = null;
    });
    _searchDebounce?.cancel();
    if (!_contentMode) return;
    if (q.trim().length < 2) {
      setState(() => _contentSearching = false);
      return;
    }
    setState(() => _contentSearching = true);
    _searchDebounce =
        Timer(const Duration(milliseconds: 350), _runContentSearch);
  }

  /// 切换「文件名 / 正文」搜索。
  void _toggleContentMode() {
    _searchDebounce?.cancel();
    setState(() {
      _contentMode = !_contentMode;
      _contentResults = null;
      _contentSearching = false;
    });
    if (_contentMode && _query.trim().length >= 2) {
      setState(() => _contentSearching = true);
      _runContentSearch();
    }
  }

  Future<void> _runContentSearch() async {
    final q = _query.trim();
    if (q.length < 2) return;
    final seq = ++_contentSeq;
    setState(() => _contentSearching = true);
    try {
      final results = await RepoSearchService.search(
        repoRoot: widget.repoDir.path,
        query: q,
        files: _allNotes,
        useDefaults: _scanner.useDefaults,
        customRules: _scanner.customRules,
      );
      if (!mounted || seq != _contentSeq) return;
      setState(() {
        _contentResults = results;
        _contentSearching = false;
      });
    } on Object {
      if (!mounted || seq != _contentSeq) return;
      setState(() {
        _contentSearching = false;
        _contentResults = const [];
      });
    }
  }

  /// 检查远端是否有新提交：先告知数量，再决定是否 pull（不改本地分支）。
  Future<void> _checkUpdates() async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(
        content: Text('正在检查远端…'),
        duration: Duration(seconds: 1),
      ),
    );
    final RemoteStatus status;
    try {
      status = await GitSyncService().checkRemote(repoDir: widget.repoDir);
    } on Object catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text('检查失败：$e')));
      }
      return;
    }
    if (!mounted) return;
    if (status.upToDate) {
      messenger.showSnackBar(const SnackBar(content: Text('已是最新')));
      return;
    }
    if (status.diverged && mounted) {
      // 远端改写了提交历史：pull 必然失败，直接询问是否重新克隆
      await _offerReclone(behind: status.behind);
      return;
    }
    final go = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('发现更新'),
        content: Text(
          status.behind > 100
              ? '远端有 100+ 个新提交，是否立即更新？'
              : '远端有 ${status.behind} 个新提交，是否立即更新？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('稍后'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('立即更新'),
          ),
        ],
      ),
    );
    if (go == true && mounted) await _pull();
  }

  /// 检查仓库内相对链接/图片是否仍然存在（只读，不改任何文件）。
  Future<void> _checkLinks() async {
    if (_linkChecking) return;
    setState(() => _linkChecking = true);
    try {
      final broken = await LinkChecker.check(
        repoRoot: widget.repoDir.path,
        files: _allNotes,
        useDefaults: _scanner.useDefaults,
        customRules: _scanner.customRules,
      );
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => _BrokenLinksSheet(broken: broken),
      );
    } on Object catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('检查失败：$e')));
      }
    } finally {
      if (mounted) setState(() => _linkChecking = false);
    }
  }

  /// 经典模式：当前目录下的子文件夹（应用 ignore 规则），排序后返回名称。
  List<String> _subDirs() {
    if (!mounted) return const [];
    final dir = _currentDir;
    if (!dir.existsSync()) return const [];
    return dir
        .listSync(followLinks: false)
        .whereType<Directory>()
        .map((d) => d.path.split(Platform.pathSeparator).last)
        .where((name) => !_scanner.isIgnored(name))
        .toList()
      ..sort(compareNatural);
  }

  /// 文件排序：名称（自然序）或最近修改（新的在前）。
  int _compareNotes(NoteFile a, NoteFile b) {
    if (!_sortByModified) return compareNatural(a.fileName, b.fileName);
    final byTime = b.modified.compareTo(a.modified);
    return byTime != 0 ? byTime : compareNatural(a.fileName, b.fileName);
  }

  /// 「仅看未读」只藏掉**有阅读记录**的文件：读到一半的也算读过，
  /// 不然筛选结果和「未读」的字面意思对不上。
  bool _hiddenByUnreadFilter(NoteFile note) =>
      _unreadOnly && _progress.containsKey(note.relativePath);

  /// 经典模式：当前目录下的 Markdown 笔记。
  List<NoteFile> _localNotes() {
    final prefix = widget.subPath.isEmpty ? '' : '${widget.subPath}/';
    return (_allNotes ?? const <NoteFile>[])
        .where((n) => n.relativePath.startsWith(prefix))
        .where((n) => !n.relativePath
            .substring(prefix.length)
            .contains('/'))
        .where((n) => !_hiddenByUnreadFilter(n))
        .toList()
      ..sort(_compareNotes);
  }

  /// 构建目录树条目：目录行就地展开/折叠（_expandedDirs 控制），
  /// 文件行点击打开。展开的目录递归展开下一层（缩进按层级递增）。
  List<_TreeEntry> _treeEntries() {
    final entries = <_TreeEntry>[];
    final allNotes = _allNotes ?? const <NoteFile>[];

    void walk(String dirRel, int depth) {
      final dir = dirRel.isEmpty
          ? _currentDir
          : Directory(
              '${widget.repoDir.path}${Platform.pathSeparator}'
              '${dirRel.replaceAll('/', Platform.pathSeparator)}',
            );
      if (!dir.existsSync()) return;
      final prefix = dirRel.isEmpty ? '' : '$dirRel/';
      // 子目录（应用 ignore 规则），自然排序
      final dirs = dir
          .listSync(followLinks: false)
          .whereType<Directory>()
          .map((d) => d.path.split(Platform.pathSeparator).last)
          .where((name) => !_scanner.isIgnored(name))
          .toList()
        ..sort(compareNatural);
      // 当前层的文件（来自全仓库扫描结果，按前缀取本层）
      final files = allNotes
          .where((n) => n.relativePath.startsWith(prefix))
          .where((n) => !n.relativePath.substring(prefix.length).contains('/'))
          .where((n) => !_hiddenByUnreadFilter(n))
          .toList()
        ..sort(_compareNotes);

      for (final name in dirs) {
        final rel = '$prefix$name';
        entries.add(_TreeEntry.dir(rel, name, depth));
        if (_expandedDirs.contains(rel)) {
          final before = entries.length;
          walk(rel, depth + 1);
          // 目录展开后没有任何可见内容时给出占位，避免"点了没反应"
          if (entries.length == before) {
            entries.add(_TreeEntry.placeholder(depth + 1));
          }
        }
      }
      for (final note in files) {
        entries.add(_TreeEntry.file(note, depth));
      }
    }

    walk(widget.subPath, 0);
    return entries;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final searching = _query.isNotEmpty;
    // 正文搜索：搜索框输入的内容去 md/ipynb/txt 正文里找（后台 isolate）
    final contentSearch = _contentMode && searching;
    final repoName = widget.repoDir.path.split(Platform.pathSeparator).last;
    final title = widget.subPath.isEmpty
        ? repoName
        : widget.subPath.split('/').last;

    // 树模式（设置开关，默认关）：目录就地展开/折叠；经典模式（默认）：
    // 点目录进入下一页（类似文件资源管理器），目录保留独立路由，
    // 指向目录的本地链接可正常跳转
    final treeMode =
        !searching && (AppPrefs.instance?.treeMode ?? false);
    final notes = searching && !_contentMode ? _searchAll() : _localNotes();
    final dirs = treeMode ? const <String>[] : _subDirs();
    final entries = treeMode ? _treeEntries() : null;
    final isEmpty = treeMode
        ? entries!.isEmpty
        : dirs.isEmpty && notes.isEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text(title, style: theme.textTheme.titleLarge),
        actions: [
          IconButton(
            onPressed: _pull,
            icon: const Icon(Icons.sync),
            tooltip: '同步',
          ),
          IconButton(
            tooltip: _sortByModified ? '按名称排序' : '按修改时间排序',
            icon: Icon(
              _sortByModified ? Icons.sort_by_alpha : Icons.schedule,
            ),
            onPressed: () =>
                setState(() => _sortByModified = !_sortByModified),
          ),
          PopupMenuButton<String>(
            tooltip: '更多',
            onSelected: (value) {
              switch (value) {
                case 'unread':
                  setState(() => _unreadOnly = !_unreadOnly);
                case 'home':
                  Navigator.popUntil(
                    context,
                    (route) =>
                        route.settings.name == 'repo-root' || route.isFirst,
                  );
                case 'updates':
                  _checkUpdates();
                case 'links':
                  _checkLinks();
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'unread',
                child: Row(
                  children: [
                    Icon(
                      _unreadOnly
                          ? Icons.check_box
                          : Icons.check_box_outline_blank,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Text(_unreadOnly ? '显示全部文件' : '仅看未读'),
                  ],
                ),
              ),
              if (widget.subPath.isNotEmpty)
                const PopupMenuItem(
                  value: 'home',
                  child: Row(
                    children: [
                      Icon(Icons.home_outlined, size: 20),
                      SizedBox(width: 12),
                      Text('回到根目录'),
                    ],
                  ),
                ),
              const PopupMenuDivider(),
              if (!LocalFolderService.isLocalMirror(widget.repoDir.path))
                const PopupMenuItem(
                  value: 'updates',
                  child: Text('检查更新'),
                ),
              const PopupMenuItem(value: 'links', child: Text('检查断链')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: SearchBar(
              hintText: _contentMode
                  ? (searching ? '搜索正文…' : '搜索正文')
                  : (searching ? '搜索中…' : '搜索文件'),
              leading: const Icon(Icons.search),
              elevation: const WidgetStatePropertyAll(0),
              constraints: const BoxConstraints(minHeight: 44),
              trailing: [
                IconButton(
                  tooltip: _contentMode ? '搜索文件名' : '搜索正文',
                  icon: Icon(
                    _contentMode ? Icons.title : Icons.subject,
                    size: 20,
                  ),
                  onPressed: _toggleContentMode,
                ),
                if (searching)
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      _searchDebounce?.cancel();
                      setState(() {
                        _query = '';
                        _contentResults = null;
                        _contentSearching = false;
                      });
                    },
                  ),
              ],
              onChanged: _onQueryChanged,
            ),
          ),
          if (_scanning || _linkChecking)
            const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: contentSearch
                ? _buildContentResults(theme)
                : RefreshIndicator(
              onRefresh: _pull,
              child: isEmpty
                  ? ListView(children: [
                      const SizedBox(height: 120),
                      // 首次扫描（无缓存）时显示进度，而不是误报「这里没有文件」
                      Center(
                        child: _allNotes == null
                            ? const CircularProgressIndicator()
                            : const Text('这里没有文件'),
                      ),
                    ])
                  : searching
                      // 搜索模式：扁平结果列表，显示相对路径
                      ? ListView(
                          padding: const EdgeInsets.only(bottom: 32),
                          children: [
                            for (final note in notes)
                              ListTile(
                                dense: true,
                                minVerticalPadding: 4,
                                leading: Icon(
                                  note.isMarkdown
                                      ? Icons.description_outlined
                                      : note.isImage
                                          ? Icons.image_outlined
                                          : Icons.code_outlined,
                                  color: note.isMarkdown
                                      ? theme.colorScheme.onSurfaceVariant
                                      : note.isImage
                                          ? theme.colorScheme.tertiary
                                          : theme.colorScheme.secondary,
                                  size: 22,
                                ),
                                title: Text(
                                  '${note.fileName}${note.extension}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodyMedium,
                                ),
                                subtitle: Text(
                                  note.relativePath,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                trailing: _fileTrailing(note, theme),
                                onTap: () => _openFile(note),
                              ),
                          ],
                        )
                      // 树模式（设置开关开启时）：就地展开/折叠的目录树
                      : treeMode
                          ? ListView(
                              padding: const EdgeInsets.only(bottom: 32),
                              children: [
                                for (final entry in entries!)
                                  if (entry.isDir)
                                    ListTile(
                                      dense: true,
                                      minVerticalPadding: 4,
                                      contentPadding: EdgeInsets.only(
                                        left: 16 + entry.depth * 20.0,
                                        right: 16,
                                      ),
                                      leading: Icon(
                                        _expandedDirs
                                                .contains(entry.dirRel)
                                            ? Icons.folder_open_outlined
                                            : Icons.folder_outlined,
                                        color: theme.colorScheme.primary,
                                        size: 22,
                                      ),
                                      title: Text(
                                        entry.name!,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.bodyMedium,
                                      ),
                                      trailing: Icon(
                                        _expandedDirs
                                                .contains(entry.dirRel)
                                            ? Icons.expand_less
                                            : Icons.expand_more,
                                        size: 18,
                                        color: theme
                                            .colorScheme.onSurfaceVariant,
                                      ),
                                      onTap: () => setState(() {
                                        if (!_expandedDirs
                                            .remove(entry.dirRel!)) {
                                          _expandedDirs.add(entry.dirRel!);
                                        }
                                      }),
                                    )
                                  else if (entry.isEmptyPlaceholder)
                                    Padding(
                                      padding: EdgeInsets.only(
                                        left: 16 + entry.depth * 20.0 + 46,
                                        top: 6,
                                        bottom: 6,
                                      ),
                                      child: Text(
                                        '空目录',
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                          color: theme
                                              .colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    )
                                  else
                                    ListTile(
                                      dense: true,
                                      minVerticalPadding: 4,
                                      // 与同层目录行同缩进（不再额外 +22，
                                      // 保证"目录与文件混排"时左侧对齐）
                                      contentPadding: EdgeInsets.only(
                                        left: 16 + entry.depth * 20.0,
                                        right: 16,
                                      ),
                                      leading: Icon(
                                        entry.note!.isMarkdown
                                            ? Icons.description_outlined
                                            : entry.note!.isImage
                                                ? Icons.image_outlined
                                                : Icons.code_outlined,
                                        color: entry.note!.isMarkdown
                                            ? theme.colorScheme
                                                .onSurfaceVariant
                                            : entry.note!.isImage
                                                ? theme.colorScheme.tertiary
                                                : theme
                                                    .colorScheme.secondary,
                                        size: 22,
                                      ),
                                      title: Text(
                                        '${entry.note!.fileName}${entry.note!.extension}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.bodyMedium,
                                      ),
                                      trailing: _fileTrailing(entry.note!, theme),
                                      onTap: () => _openFile(entry.note!),
                                    ),
                              ],
                            )
                          // 经典模式（默认）：点目录进入下一页，
                          // 类似文件资源管理器；目录保留独立路由
                          : ListView(
                              padding: const EdgeInsets.only(bottom: 32),
                              children: [
                                for (final name in dirs)
                                  ListTile(
                                    dense: true,
                                    minVerticalPadding: 4,
                                    leading: Icon(
                                      Icons.folder_outlined,
                                      color: theme.colorScheme.primary,
                                      size: 22,
                                    ),
                                    title: Text(
                                      name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodyMedium,
                                    ),
                                    onTap: () => Navigator.push(
                                      context,
                                      MaterialPageRoute<void>(
                                        builder: (_) => RepoPage(
                                          repoDir: widget.repoDir,
                                          subPath: widget.subPath.isEmpty
                                              ? name
                                              : '${widget.subPath}/$name',
                                        ),
                                      ),
                                    ),
                                  ),
                                for (final note in notes)
                                  ListTile(
                                    dense: true,
                                    minVerticalPadding: 4,
                                    leading: Icon(
                                      note.isMarkdown
                                          ? Icons.description_outlined
                                          : note.isImage
                                              ? Icons.image_outlined
                                              : Icons.code_outlined,
                                      color: note.isMarkdown
                                          ? theme
                                              .colorScheme.onSurfaceVariant
                                          : note.isImage
                                              ? theme.colorScheme.tertiary
                                              : theme.colorScheme.secondary,
                                      size: 22,
                                    ),
                                    title: Text(
                                      '${note.fileName}${note.extension}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodyMedium,
                                    ),
                                    trailing: _fileTrailing(note, theme),
                                    onTap: () => _openFile(note),
                                  ),
                              ],
                            ),
            ),
          ),
        ],
      ),
    );
  }

  /// 正文搜索结果：文件分组 + 命中摘要 + 命中次数。
  Widget _buildContentResults(ThemeData theme) {
    if (_query.trim().length < 2) {
      return const Center(child: Text('输入至少 2 个字符搜索正文'));
    }
    if (_contentSearching && _contentResults == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final results = _contentResults ?? const <FileSearchResult>[];
    if (results.isEmpty) {
      return Center(
        child: Text(_contentSearching ? '搜索中…' : '没有匹配的正文'),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 32),
      itemCount: results.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final result = results[i];
        final name = result.relativePath.split('/').last;
        return ListTile(
          title: Row(
            children: [
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              Text(
                '${result.matches} 处',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                result.relativePath,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              for (final snippet in result.snippets)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: SearchSnippetText(snippet: snippet),
                ),
            ],
          ),
          onTap: () => _openByRelativePath(result.relativePath),
        );
      },
    );
  }

  /// 正文结果点击：优先复用已扫描的 NoteFile，冷启动时按路径现造一个。
  /// 从正文搜索进入时带上检索词，阅读页会自动定位到第一处命中。
  void _openByRelativePath(String relativePath) {
    final findQuery =
        _contentMode && _query.trim().length >= 2 ? _query.trim() : null;
    for (final note in _allNotes ?? const <NoteFile>[]) {
      if (note.relativePath == relativePath) {
        _openFile(note, findQuery: findQuery);
        return;
      }
    }
    final file = File(
      '${widget.repoDir.path}${Platform.pathSeparator}'
      '${relativePath.replaceAll('/', Platform.pathSeparator)}',
    );
    if (!file.existsSync()) return;
    final stat = file.statSync();
    _openFile(
      NoteFile(
        relativePath: relativePath,
        absolutePath: file.path,
        modified: stat.modified,
        sizeBytes: stat.size,
      ),
      findQuery: findQuery,
    );
  }

  /// 全仓库扁平搜索（仅搜索模式使用）。
  List<NoteFile> _searchAll() {
    return (_allNotes ?? const <NoteFile>[])
        .where((n) =>
            n.fileName.toLowerCase().contains(_query) ||
            n.relativePath.toLowerCase().contains(_query))
        .toList();
  }

  void _openFile(NoteFile note, {String? findQuery}) {
    _markOpened(note);
    unawaited(
      openNoteFile(
        context,
        repoRoot: widget.repoDir.path,
        note: note,
        findQuery: findQuery,
      ).then((_) {
        // 从阅读页回来：刷新阅读状态（读到 N% / 已读完）
        if (!mounted) return;
        setState(() {
          _progress = RepoMeta.readAllProgress(widget.repoDir.path);
        });
      }),
    );
  }

  Future<void> _pull() async {
    // 本地文件夹镜像：没有 git 远端，「同步」= 重新镜像授权文件夹的最新内容
    if (LocalFolderService.isLocalMirror(widget.repoDir.path)) {
      final folder = await LocalFolderService.matchMirror(
        widget.repoDir.path,
      );
      if (folder == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('本地文件夹授权已移除')),
          );
        }
        return;
      }
      try {
        await LocalFolderService.syncFolder(folder);
        await _refresh();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('已刷新'),
              duration: Duration(seconds: 1),
            ),
          );
        }
      } on Object catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('刷新失败: $e')));
        }
      }
      return;
    }
    try {
      final outcome = await runWithPullProgress<PullOutcome>(
        context,
        title: '正在拉取',
        action: (onProgress) => GitSyncService().pull(
          repoDir: widget.repoDir,
          onProgress: (p) => onProgress(
            widget.repoDir.path.split(Platform.pathSeparator).last,
            p,
          ),
        ),
      );
      RepoMeta.touchSynced(widget.repoDir.path);
      if (outcome.result != PullResult.upToDate) {
        // 记录本次 pull 带来的新增/修改，供列表打标（打开文件后清除）
        RepoMeta.setRecentChanges(widget.repoDir.path, outcome.changes);
        _loadRecentChanges();
      }
      await _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              outcome.result == PullResult.upToDate
                  ? '已是最新'
                  : '已更新（${outcome.changes.length} 个文件）',
            ),
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } on SyncException catch (e) {
      if (!mounted) return;
      if (e.diverged) {
        // 远端改写了提交历史，本地永远无法 fast-forward：询问是否重新克隆
        await _offerReclone();
      } else {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('同步失败: $e')));
      }
    } on Exception catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('同步失败: $e')));
      }
    }
  }

  /// 历史分叉时询问是否重新克隆：删除本地仓库后按 RepoMeta 记录的来源
  /// 重新下载。阅读进度、收藏、更新标记都存在仓库外的 meta 里，不受影响。
  Future<void> _offerReclone({int behind = 0}) async {
    final go = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('远端提交历史已被改写'),
        content: Text(
          behind > 0
              ? '远端重写了提交记录，本地无法直接更新（落后 $behind 个新提交）。'
                  '重新克隆会删除本地仓库并重新下载全部内容；'
                  '阅读进度与收藏会保留。'
              : '远端重写了提交记录，本地无法直接更新。'
                  '重新克隆会删除本地仓库并重新下载全部内容；'
                  '阅读进度与收藏会保留。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('稍后'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('重新克隆'),
          ),
        ],
      ),
    );
    if (go == true && mounted) await _reclone();
  }

  /// 删除本地仓库目录并按原 URL 重新克隆（进度/收藏等元数据保留）。
  Future<void> _reclone() async {
    final meta = RepoMeta.read(widget.repoDir.path);
    final url = meta?.url;
    if (url == null || url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('缺少仓库来源信息，请删除该仓库后重新添加'),
        ),
      );
      return;
    }
    final name = widget.repoDir.path.split(Platform.pathSeparator).last;
    var owner = '';
    try {
      final segments = Uri.parse(url).path.split('/')..removeWhere((s) => s.isEmpty);
      if (segments.length >= 2) owner = segments[segments.length - 2];
    } on Object {
      // 解析失败时 owner 留空，仅影响展示
    }
    final info = RepoInfo(
      platform: guessPlatform(url),
      owner: owner,
      name: name,
      cloneUrl: url,
    );
    final rootNav = Navigator.of(context, rootNavigator: true);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 24),
            Expanded(child: Text('正在重新克隆仓库…')),
          ],
        ),
      ),
    );
    try {
      await GitSyncService().deleteRepo(widget.repoDir.path);
      await GitSyncService().clone(
        repo: info,
        parentDir: widget.repoDir.parent,
      );
      RepoMeta.writeClone(
        widget.repoDir.path,
        url: url,
        branch: GitSyncService.readHeadBranch(widget.repoDir.path),
      );
      await _refresh();
    } on Exception catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('重新克隆失败: $e')));
      }
    } finally {
      if (rootNav.canPop()) rootNav.pop();
    }
  }
}

/// 目录树条目：目录行（可折叠）、文件行或空目录占位。
class _TreeEntry {
  const _TreeEntry._({
    required this.depth,
    this.dirRel,
    this.name,
    this.note,
    this.isEmptyPlaceholder = false,
  });

  /// 目录行：[dirRel] 为相对仓库根的路径，点击切换展开/折叠。
  factory _TreeEntry.dir(String dirRel, String name, int depth) =>
      _TreeEntry._(dirRel: dirRel, name: name, depth: depth);

  /// 文件行：直接打开 [note]。
  factory _TreeEntry.file(NoteFile note, int depth) =>
      _TreeEntry._(note: note, depth: depth);

  /// 空目录占位（展开后无可见内容时避免"点了没反应"）。
  factory _TreeEntry.placeholder(int depth) =>
      const _TreeEntry._(depth: 0, isEmptyPlaceholder: true);

  final int depth;
  final String? dirRel;
  final String? name;
  final NoteFile? note;
  final bool isEmptyPlaceholder;

  bool get isDir => dirRel != null;
}

/// 断链清单：按来源文件分组展示，可一键复制。
class _BrokenLinksSheet extends StatelessWidget {
  const _BrokenLinksSheet({required this.broken});

  final List<BrokenLink> broken;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final height = MediaQuery.of(context).size.height * 0.6;
    return SizedBox(
      height: height,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    broken.isEmpty ? '没有发现断链' : '断链 ${broken.length} 处',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                if (broken.isNotEmpty)
                  TextButton(
                    onPressed: () async {
                      final text = broken
                          .map((b) =>
                              '${b.sourceRelativePath} -> ${b.target}')
                          .join('\n');
                      await Clipboard.setData(ClipboardData(text: text));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('已复制断链清单')),
                        );
                      }
                    },
                    child: const Text('复制清单'),
                  ),
                IconButton(
                  tooltip: '关闭',
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: broken.isEmpty
                ? Center(
                    child: Text(
                      '所有相对链接与图片都能在仓库里找到',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : ListView.separated(
                    itemCount: broken.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final item = broken[i];
                      return ListTile(
                        dense: true,
                        leading: Icon(
                          item.isImage
                              ? Icons.broken_image_outlined
                              : Icons.link_off,
                          size: 20,
                          color: theme.colorScheme.error,
                        ),
                        title: Text(
                          item.target,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          item.sourceRelativePath,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
