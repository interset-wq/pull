import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../git/repo_meta.dart';
import '../git/sync_service.dart';
import '../local/local_folder_service.dart';
import '../notes/note_index.dart';
import '../notes/note_scanner.dart';
import '../platforms/git_platform.dart';
import '../platforms/repo_info.dart';
import '../theme/app_prefs.dart';
import '../utils/dir_size.dart' show formatBytes;
import 'bookmarks_page.dart';
import 'global_search_page.dart';
import 'markdown_viewer.dart';
import 'open_note.dart';
import 'pull_progress.dart';
import 'repo_page.dart';
import 'settings_page.dart';
import 'tag_page.dart';
import 'updates_page.dart';

/// 首页：已克隆仓库卡片 + 添加仓库（克隆）。
/// 移动端优先：大卡片、下拉刷新、底部导航结构。
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _sync = GitSyncService();
  List<Directory>? _repos;
  List<LocalFolder>? _localFolders;
  bool _cloning = false;
  bool _updatingAll = false;

  /// 各仓库/镜像里尚未读的「新增/更新」条目总数（更新收件箱的角标）。
  int _updateCount = 0;

  /// 最近书签（首页横滑条，最多 5 条，跨仓库）。
  List<({String repoName, Directory root, Bookmark bookmark})>
      _recentBookmarks = const [];

  Future<Directory> get _reposRoot async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}${Platform.pathSeparator}repos');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  @override
  void initState() {
    super.initState();
    _loadRepos();
    _loadLocals();
    _silentPullAll();
  }

  Future<void> _loadLocals() async {
    final folders = await LocalFolderService.listFolders();
    if (!mounted) return;
    setState(() => _localFolders = folders);
    unawaited(_refreshUpdateCount());
    unawaited(_loadBookmarks());
  }

  /// 重新统计更新收件箱的未读数（仓库 + 本地镜像的 recentChanges）。
  Future<void> _refreshUpdateCount() async {
    var total = 0;
    for (final dir in _repos ?? const <Directory>[]) {
      total += RepoMeta.readRecentChanges(dir.path).length;
    }
    for (final folder in _localFolders ?? const <LocalFolder>[]) {
      final dir = await LocalFolderService.mirrorDir(folder.name);
      total += RepoMeta.readRecentChanges(dir.path).length;
    }
    if (!mounted || total == _updateCount) return;
    setState(() => _updateCount = total);
  }

  /// 打开更新收件箱：一次性汇总所有来源的未读更新。
  Future<void> _openUpdates() async {
    final sources = <({String name, Directory root})>[];
    for (final dir in _repos ?? const <Directory>[]) {
      sources.add((
        name: dir.path.split(Platform.pathSeparator).last,
        root: dir,
      ));
    }
    for (final folder in _localFolders ?? const <LocalFolder>[]) {
      sources.add((
        name: folder.name,
        root: await LocalFolderService.mirrorDir(folder.name),
      ));
    }
    if (!mounted) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(builder: (_) => UpdatesPage(sources: sources)),
    );
    if (!mounted) return;
    await _refreshUpdateCount();
  }

  /// 收集跨仓库/本地镜像的书签，首页只展示最近 5 条。
  Future<void> _loadBookmarks() async {
    final out = <({String repoName, Directory root, Bookmark bookmark})>[];
    for (final dir in _repos ?? const <Directory>[]) {
      final name = dir.path.split(Platform.pathSeparator).last;
      for (final bookmark in RepoMeta.readBookmarks(dir.path)) {
        out.add((repoName: name, root: dir, bookmark: bookmark));
      }
    }
    for (final folder in _localFolders ?? const <LocalFolder>[]) {
      final dir = await LocalFolderService.mirrorDir(folder.name);
      for (final bookmark in RepoMeta.readBookmarks(dir.path)) {
        out.add((repoName: folder.name, root: dir, bookmark: bookmark));
      }
    }
    out.sort((a, b) => b.bookmark.createdAt.compareTo(a.bookmark.createdAt));
    if (!mounted) return;
    setState(() => _recentBookmarks = out.take(5).toList());
  }

  Future<void> _openBookmark(
    ({String repoName, Directory root, Bookmark bookmark}) entry,
  ) async {
    final bookmark = entry.bookmark;
    final file = File(
      '${entry.root.path}${Platform.pathSeparator}'
      '${bookmark.relativePath.replaceAll('/', Platform.pathSeparator)}',
    );
    if (!file.existsSync()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('文件已不存在；书签可在书签页删除')),
      );
      return;
    }
    final stat = file.statSync();
    await openNoteFile(
      context,
      repoRoot: entry.root.path,
      note: NoteFile(
        relativePath: bookmark.relativePath,
        absolutePath: file.path,
        modified: stat.modified,
        sizeBytes: stat.size,
      ),
      initialFraction: bookmark.fraction,
    );
    if (!mounted) return;
    await _loadBookmarks();
  }

  /// 全部书签页（跨仓库）。
  Future<void> _openBookmarks() async {
    final sources = <BookmarkSource>[];
    for (final dir in _repos ?? const <Directory>[]) {
      sources.add(BookmarkSource(
        name: dir.path.split(Platform.pathSeparator).last,
        root: dir,
      ));
    }
    for (final folder in _localFolders ?? const <LocalFolder>[]) {
      sources.add(BookmarkSource(
        name: folder.name,
        root: await LocalFolderService.mirrorDir(folder.name),
      ));
    }
    if (!mounted) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(builder: (_) => BookmarksPage(sources: sources)),
    );
    if (!mounted) return;
    await _loadBookmarks();
  }

  /// 添加本地文件夹（系统选择器授权 + 首次镜像）。
  Future<void> _addLocalFolder() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final folder = await LocalFolderService.addFolder();
      if (folder != null) {
        messenger.showSnackBar(
          SnackBar(content: Text('已添加「${folder.name}」')),
        );
      }
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('添加失败: $e')));
    }
    await _loadLocals();
  }

  /// 打开本地文件夹：先重镜像拿到最新内容，再进仓库页（复用）。
  Future<void> _openLocal(LocalFolder folder) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await LocalFolderService.syncFolder(folder);
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('刷新失败: $e')));
      // 镜像失败仍打开旧内容
    }
    final dir = await LocalFolderService.mirrorDir(folder.name);
    if (!mounted) return;
    // 增量同步会跳过「编辑器保存过但没写回源文件夹」的文件；这里明确
    // 提示，避免用户以为源文件夹已经是最新
    final pending = LocalFolderService.pendingCount(dir.path);
    if (pending > 0) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('$pending 个修改尚未写回原文件夹（设置 → 未写回的修改）'),
        ),
      );
    }
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => RepoPage(repoDir: dir),
        settings: const RouteSettings(name: 'repo-root'),
      ),
    );
  }

  /// 仅重镜像（本地卡片上的刷新按钮）。
  Future<void> _syncLocal(LocalFolder folder) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await LocalFolderService.syncFolder(folder);
      final dir = await LocalFolderService.mirrorDir(folder.name);
      final pending = LocalFolderService.pendingCount(dir.path);
      messenger.showSnackBar(
        SnackBar(
          content: Text(pending > 0 ? '已刷新；$pending 个修改尚未写回' : '已刷新'),
          duration: const Duration(seconds: 2),
        ),
      );
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('刷新失败: $e')));
    }
  }

  Future<void> _confirmRemoveLocal(LocalFolder folder) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('移除本地文件夹'),
        content: Text(
          '将移除「${folder.name}」的访问授权与镜像，原文件夹不受影响。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('移除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await LocalFolderService.removeFolder(folder);
    await _loadLocals();
  }

  /// 启动时后台静默更新所有仓库：不转圈、不弹提示，完成后仅刷新列表。
  /// 受设置「自动拉取同步」开关控制（默认关闭——下拉刷新即可手动同步）。
  Future<void> _silentPullAll() async {
    if (!(AppPrefs.instance?.silentPull ?? false)) return;
    // 等首轮仓库列表就绪再更新，避免与克隆/手动更新并发
    await _loadRepos();
    final repos = _repos;
    if (repos == null || repos.isEmpty) return;
    final sync = GitSyncService();
    for (final repo in repos) {
      try {
        final outcome = await sync.pull(repoDir: repo);
        RepoMeta.touchSynced(repo.path);
        if (outcome.result != PullResult.upToDate) {
          RepoMeta.setRecentChanges(repo.path, outcome.changes);
        }
      } on Exception {
        // 静默失败：离线时保持本地内容可用
      }
    }
    await _loadRepos();
  }

  /// 打开标签页：仓库 + 本地文件夹镜像一起聚合（跨来源）。
  Future<void> _openTags(List<Directory> repos) async {
    final roots = <Directory>[...repos];
    for (final folder in _localFolders ?? const <LocalFolder>[]) {
      roots.add(await LocalFolderService.mirrorDir(folder.name));
    }
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => TagPage(roots: roots)),
    );
  }

  Future<void> _loadRepos() async {
    List<Directory> dirs;
    try {
      final root = await _reposRoot;
      dirs = root
          .listSync(followLinks: false)
          .whereType<Directory>()
          .where((d) => Directory('${d.path}${Platform.pathSeparator}.git')
              .existsSync())
          .toList();
    } on Object {
      // 取不到文档目录（权限异常/测试环境）时不要永远转圈，按空列表展示
      dirs = const [];
    }
    if (!mounted) return;
    // 置顶（Roadmap「仓库管理·仓库置顶」）固定在最前，其余保持原顺序
    dirs.sort((a, b) {
      final pa = RepoMeta.isPinned(a.path) ? 0 : 1;
      final pb = RepoMeta.isPinned(b.path) ? 0 : 1;
      return pa.compareTo(pb);
    });
    setState(() => _repos = dirs);
    unawaited(_refreshUpdateCount());
    unawaited(_loadBookmarks());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final repos = _repos ?? const <Directory>[];
    final locals = _localFolders ?? const <LocalFolder>[];
    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        // 头部左侧用 logo 代替文字品牌（文字受系统字体影响，行为难控）
        title: Image.asset(
          'assets/icons/icon_book.png',
          width: 40,
          height: 40,
        ),
        actions: [
          IconButton(
            tooltip: '搜索全部仓库',
            icon: const Icon(Icons.search),
            onPressed: repos.isEmpty
                ? null
                : () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => GlobalSearchPage(repos: repos),
                      ),
                    ),
          ),
          IconButton(
            tooltip: '标签',
            icon: const Icon(Icons.sell_outlined),
            onPressed: (repos.isEmpty && locals.isEmpty)
                ? null
                : () => _openTags(repos),
          ),
          IconButton(
            tooltip: '全部更新',
            icon: _updatingAll
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.cloud_sync_outlined),
            onPressed:
                (_cloning || _updatingAll || _repos == null) ? null : _pullAll,
          ),
          IconButton(
            tooltip: '更新收件箱',
            icon: Badge(
              isLabelVisible: _updateCount > 0,
              label: Text(_updateCount > 99 ? '99+' : '$_updateCount'),
              child: const Icon(Icons.inbox_outlined),
            ),
            onPressed: (repos.isEmpty && locals.isEmpty) ? null : _openUpdates,
          ),
          if (AppPrefs.instance case final prefs?) ...[
            IconButton(
              tooltip: '设置',
              icon: const Icon(Icons.settings_outlined),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => SettingsPage(prefs: prefs),
                ),
              ),
            ),
            ListenableBuilder(
              listenable: prefs,
              builder: (context, _) {
                return PopupMenuButton<ThemeMode>(
                  tooltip: '主题',
                  icon: Icon(
                    switch (prefs.mode) {
                      ThemeMode.system => Icons.brightness_auto,
                      ThemeMode.light => Icons.light_mode,
                      ThemeMode.dark => Icons.dark_mode,
                    },
                  ),
                  onSelected: (m) => prefs.setMode(m),
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: ThemeMode.system,
                      child: Row(
                        children: [
                          Icon(Icons.brightness_auto, size: 20),
                          SizedBox(width: 12),
                          Text('跟随系统'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: ThemeMode.light,
                      child: Row(
                        children: [
                          Icon(Icons.light_mode, size: 20),
                          SizedBox(width: 12),
                          Text('浅色'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: ThemeMode.dark,
                      child: Row(
                        children: [
                          Icon(Icons.dark_mode, size: 20),
                          SizedBox(width: 12),
                          Text('深色'),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _cloning ? null : _showCloneDialog,
        child: _cloning
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.add),
      ),
      body: _repos == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadRepos,
              child: repos.isEmpty && locals.isEmpty
                  ? _EmptyState(
                      onAdd: _showCloneDialog,
                      onAddLocal: _addLocalFolder,
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                      itemCount: locals.length + repos.length + 1,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (context, i) {
                        if (i == 0) {
                          final resume = _continueReading(repos);
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (resume != null) ...[
                                _buildContinueCard(resume),
                                const SizedBox(height: 16),
                              ],
                              _buildFileStrip(
                                repos,
                                title: '⭐ 收藏',
                                files: _collectStarred(repos),
                                starred: true,
                              ),
                              if (_collectStarred(repos).isNotEmpty &&
                                  _collectRecents(repos).isNotEmpty)
                                const SizedBox(height: 12),
                              _buildFileStrip(
                                repos,
                                title: '最近阅读',
                                files: _collectRecents(repos),
                                starred: false,
                              ),
                              if (_recentBookmarks.isNotEmpty) ...[
                                const SizedBox(height: 12),
                                _buildBookmarkStrip(theme),
                              ],
                              const SizedBox(height: 16),
                              if (locals.isEmpty)
                                // 空态：一张添加入口卡（避免孤立标题悬在仓库卡上方）
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: Card(
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                      side: BorderSide(
                                        color: theme.colorScheme.outlineVariant,
                                      ),
                                    ),
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(16),
                                      onTap: _addLocalFolder,
                                      child: Padding(
                                        padding: const EdgeInsets.all(16),
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.create_new_folder_outlined,
                                              color:
                                                  theme.colorScheme.tertiary,
                                              size: 32,
                                            ),
                                            const SizedBox(width: 16),
                                            Expanded(
                                              child: Text(
                                                '添加本地文件夹',
                                                style: theme
                                                    .textTheme.titleMedium,
                                              ),
                                            ),
                                            Text(
                                              'Markdown / Notebook',
                                              style: theme
                                                  .textTheme.bodySmall
                                                  ?.copyWith(
                                                color: theme.colorScheme
                                                    .onSurfaceVariant,
                                              ),
                                            ),
                                            const Icon(Icons.chevron_right),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                )
                              else ...[
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '本地文件夹',
                                        style: theme.textTheme.titleMedium,
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: '添加本地文件夹',
                                      icon: const Icon(
                                        Icons.create_new_folder_outlined,
                                      ),
                                      onPressed: _addLocalFolder,
                                    ),
                                  ],
                                ),
                                for (final folder in locals)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: _LocalCard(
                                      name: folder.name,
                                      onTap: () => _openLocal(folder),
                                      onRefresh: () => _syncLocal(folder),
                                      onRemove: () =>
                                          _confirmRemoveLocal(folder),
                                    ),
                                  ),
                              ],
                            ],
                          );
                        }
                        if (i <= locals.length) {
                          // 本地卡片已在上方汇总区渲染，跳过占位
                          return const SizedBox.shrink();
                        }
                        final repo = repos[i - locals.length - 1];
                        final name =
                            repo.path.split(Platform.pathSeparator).last;
                        final meta = RepoMeta.read(repo.path);
                        return _RepoCard(
                          name: name,
                          source: meta?.source,
                          lastOpened: meta?.lastOpened,
                          syncedAt: meta?.syncedAt,
                          pinned: RepoMeta.isPinned(repo.path),
                          onTogglePin: () {
                            RepoMeta.togglePin(repo.path);
                            _loadRepos();
                          },
                          onTap: () => _openRepo(repo),
                          onDelete: () => _confirmDelete(repo),
                        );
                      },
                    ),
            ),
    );
  }

  /// 「继续阅读」候选：最近阅读里第一篇文章，且进度在 (2%, 98%) 之间
  /// （刚开始读的 0% 和已读完的不值得单独占一张卡）。
  (Directory, String, double)? _continueReading(List<Directory> repos) {
    for (final (repo, relPath) in _collectRecents(repos)) {
      final (fraction, _) = RepoMeta.readProgressInfo(repo.path, relPath);
      if (fraction <= 0.02 || fraction >= 0.98) continue;
      final file = File(
        '${repo.path}${Platform.pathSeparator}'
        '${relPath.replaceAll('/', Platform.pathSeparator)}',
      );
      if (!file.existsSync()) continue;
      return (repo, relPath, fraction);
    }
    return null;
  }

  /// 首页顶部「继续阅读」卡：直接回到上次读到的位置。
  Widget _buildContinueCard((Directory, String, double) resume) {
    final (repo, relPath, fraction) = resume;
    final theme = Theme.of(context);
    final repoName = repo.path.split(Platform.pathSeparator).last;
    final fileName = relPath.split('/').last;
    return Material(
      color: theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _openRecentFile(repo, relPath),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(
                Icons.play_circle_outline,
                color: theme.colorScheme.primary,
                size: 30,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '继续阅读',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$repoName · 已读 ${(fraction * 100).round()}%',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }

  /// 首页书签条：最近 5 条书签，点卡片直达，「全部」进跨仓库书签页。
  Widget _buildBookmarkStrip(ThemeData theme) {
    if (_recentBookmarks.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('书签', style: theme.textTheme.titleMedium),
            ),
            TextButton(
              onPressed: _openBookmarks,
              child: const Text('全部'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 76,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _recentBookmarks.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final entry = _recentBookmarks[i];
              final fileName = entry.bookmark.relativePath.split('/').last;
              return Material(
                color: theme.colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => _openBookmark(entry),
                  child: Container(
                    width: 210,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.bookmark_outline,
                          size: 22,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                entry.bookmark.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '$fileName · '
                                '${(entry.bookmark.fraction * 100).round()}%',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color:
                                      theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// 首页横滑文件条（收藏 / 最近阅读）。
  Widget _buildFileStrip(
    List<Directory> repos, {
    required String title,
    required List<(Directory, String)> files,
    required bool starred,
  }) {
    if (files.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final accent = starred
        ? const Color(0xFFF5B301)
        : theme.colorScheme.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        SizedBox(
          height: 76,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: files.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final (repo, relPath) = files[i];
              final repoName =
                  repo.path.split(Platform.pathSeparator).last;
              final fileName = relPath.split('/').last;
              final parentDir = relPath.split('/')
                ..removeLast()
                ..removeWhere((s) => s.isEmpty);
              final subtitle = parentDir.isEmpty
                  ? repoName
                  : '$repoName · ${parentDir.last}';
              return Material(
                color: theme.colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => _openRecentFile(repo, relPath),
                  child: Container(
                    width: 190,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          starred
                              ? Icons.star_rounded
                              : Icons.history_rounded,
                          size: 22,
                          color: accent,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                fileName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium
                                    ?.copyWith(fontWeight: FontWeight.w500),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color:
                                      theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// 跨仓库聚合收藏文章（每仓库按收藏先后）。
  List<(Directory, String)> _collectStarred(List<Directory> repos) {
    final out = <(Directory, String)>[];
    for (final repo in repos) {
      for (final rel in RepoMeta.starredFiles(repo.path)) {
        out.add((repo, rel));
      }
    }
    return out;
  }

  /// 跨仓库聚合最近阅读（全局新→旧）。
  List<(Directory, String)> _collectRecents(List<Directory> repos) {
    if (repos.isEmpty) return const [];
    final root = Directory(repos.first.parent.path);
    final byName = {
      for (final d in repos)
        d.path.split(Platform.pathSeparator).last: d,
    };
    return RepoMeta.readRecents(root.path)
        .take(AppPrefs.instance?.recentsLimit ?? 5)
        .map((e) => byName[e.$1] == null ? null : (byName[e.$1]!, e.$2))
        .whereType<(Directory, String)>()
        .toList();
  }

  /// 打开最近阅读的文章（仅 Markdown；文件已删除时忽略）。
  void _openRecentFile(Directory repo, String relPath) {
    final file = File(
      '${repo.path}${Platform.pathSeparator}'
      '${relPath.replaceAll('/', Platform.pathSeparator)}',
    );
    if (!file.existsSync()) return;
    final stat = file.statSync();
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => MarkdownViewerPage(
          note: NoteFile(
            relativePath: relPath,
            absolutePath: file.path,
            modified: stat.modified,
            sizeBytes: stat.size,
          ),
          repoRoot: repo.path,
        ),
      ),
    ).then((_) {
      // 阅读页会更新进度：回到首页刷新「继续阅读」与「最近阅读」
      if (mounted) setState(() {});
    });
  }

  Future<void> _openRepo(Directory repoDir) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => RepoPage(repoDir: repoDir),
        settings: const RouteSettings(name: 'repo-root'),
      ),
    );
    if (!mounted) return;
    // 仓库页里打开文件会清掉更新标记、拉取会新增标记
    await _refreshUpdateCount();
  }

  Future<void> _confirmDelete(Directory repo) async {
    final name = repo.path.split(Platform.pathSeparator).last;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除仓库'),
        content: Text('将从本地删除 $name 及其全部内容，远端仓库不受影响。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _sync.deleteRepo(repo.path);
      RepoMeta.remove(repo.path);
      NoteIndexCache.remove(repo.path);
      await _loadRepos();
    } on Exception catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('删除失败: $e')));
      }
    }
  }

  /// 顺序 pull 所有本地仓库，汇总结果提示。
  Future<void> _pullAll() async {
    final repos = _repos;
    if (repos == null || repos.isEmpty) return;
    setState(() => _updatingAll = true);
    var updated = 0;
    var failed = 0;
    final sync = GitSyncService();
    try {
      await runWithPullProgress<void>(
        context,
        title: '正在更新全部仓库',
        action: (onProgress) async {
          for (var i = 0; i < repos.length; i++) {
            final repo = repos[i];
            final name = repo.path.split(Platform.pathSeparator).last;
            final label = '(${i + 1}/${repos.length}) $name';
            onProgress(label, null);
            try {
              final outcome = await sync.pull(
                repoDir: repo,
                onProgress: (p) => onProgress(label, p),
              );
              RepoMeta.touchSynced(repo.path);
              if (outcome.result != PullResult.upToDate) {
                RepoMeta.setRecentChanges(repo.path, outcome.changes);
                updated++;
              }
            } on Exception {
              failed++;
            }
          }
        },
      );
      await _loadRepos();
    } finally {
      if (mounted) {
        setState(() => _updatingAll = false);
        final msg = failed > 0
            ? '更新完成：$updated 个有更新，$failed 个失败'
            : updated > 0
                ? '已更新 $updated 个仓库'
                : '所有仓库均已是最新';
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(msg)));
      }
    }
  }

  /// 解析克隆输入：完整 URL 原样返回；
  /// `owner/repo` / `repo` 按设置的默认平台与用户名拼接完整地址。
  String? _resolveCloneUrl(String input, AppPrefs prefs) {
    final v = input.trim();
    if (v.isEmpty) return null;
    if (v.startsWith('http://') || v.startsWith('https://')) return v;
    final parts = v.split('/').where((e) => e.isNotEmpty).toList();
    final owner = switch (parts.length) {
      2 => parts[0],
      1 => prefs.defaultOwner,
      _ => null,
    };
    final repo = parts.last;
    if (owner == null || owner.isEmpty || repo.isEmpty) return null;
    // 「其他」平台没有可拼接的域名（自建 Gitea 等必须给完整 URL）
    if (prefs.platform.webBase.isEmpty) return null;
    return '${prefs.platform.webBase}/$owner/$repo.git';
  }

  /// 仓库地址匹配（剪贴板快速导入）：任意域名下的 `host/owner/repo`，
  /// 不限于内置平台——自建 Gitea / GitLab 的完整 URL 也能直接导入。
  static final RegExp _repoUrlRegExp = RegExp(
    r'https?://(?:www\.)?[^\s/]+/[\w.\-]+/[\w.\-]+',
    caseSensitive: false,
  );

  /// 剪贴板快速导入（Roadmap「导入与同步体验」）：克隆页打开时读取剪贴板，
  /// 内容是仓库地址（完整 URL 或 `owner/repo` 短格式）则自动填充；
  /// 识别失败静默不打扰。
  Future<void> _prefillFromClipboard(TextEditingController ctrl) async {
    try {
      final text = (await Clipboard.getData('text/plain'))?.text?.trim();
      if (text == null || text.isEmpty || text.length > 500) return;
      final isUrl = text.startsWith('http://') || text.startsWith('https://');
      final ok = isUrl
          ? _repoUrlRegExp.hasMatch(text)
          : RegExp(r'^[\w.\-]+/[\w.\-]+$').hasMatch(text);
      if (!ok) return;
      ctrl.text = text;
    } catch (_) {
      // 剪贴板不可用（部分设备权限受限）时静默跳过
    }
  }

  Future<void> _showCloneDialog() async {
    final urlCtrl = TextEditingController();
    final prefs = AppPrefs.instance;
    unawaited(_prefillFromClipboard(urlCtrl));
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('添加仓库'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: urlCtrl,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                labelText: '仓库地址',
                hintText: 'notes · owner/notes · https://…',
                helperText: prefs == null
                    ? null
                    : '仅输仓库名时按 ${prefs.platform.displayName} / '
                        '${prefs.defaultOwner.isEmpty ? '<默认用户名>' : prefs.defaultOwner} 拼接'
                        '（可在设置中修改）',
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('克隆'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (!mounted) return;

    final url = prefs == null
        ? urlCtrl.text.trim()
        : _resolveCloneUrl(urlCtrl.text, prefs);
    if (url == null || url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('无法解析地址：可输入完整 URL、用户名/仓库名，'
              '或在设置中先填写默认用户名'),
        ),
      );
      return;
    }
    final name = url.split('/').last.replaceAll('.git', '');
    final info = RepoInfo(
      platform: guessPlatform(url),
      owner: url.split('/').reversed.elementAt(1),
      name: name,
      cloneUrl: url,
    );
    setState(() => _cloning = true);
    final rootNav = Navigator.of(context, rootNavigator: true);
    var busyClosed = false;
    void closeBusy() {
      if (busyClosed) return;
      busyClosed = true;
      rootNav.pop();
    }

    // 进度对话框：对象传输阶段显示百分比与已下载体积，可取消
    final cancelToken = CloneCancelToken();
    final progress = ValueNotifier<CloneProgress?>(null);
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          content: ValueListenableBuilder<CloneProgress?>(
            valueListenable: progress,
            builder: (dialogContext, p, _) {
              final fraction = p?.fraction;
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('正在克隆仓库…'),
                  const SizedBox(height: 16),
                  LinearProgressIndicator(value: fraction),
                  const SizedBox(height: 8),
                  Text(
                    p == null
                        ? '连接中…'
                        : fraction == null
                            ? formatBytes(p.receivedBytes)
                            : '${p.receivedObjects} / ${p.totalObjects} 个对象 · '
                                '${formatBytes(p.receivedBytes)}',
                    style: Theme.of(dialogContext).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: cancelToken.cancel,
                      child: const Text('取消'),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
    try {
      await _sync.clone(
        repo: info,
        parentDir: await _reposRoot,
        onProgress: (p) {
          if (!busyClosed) progress.value = p;
        },
        cancelToken: cancelToken,
      );
      final root = await _reposRoot;
      final clonePath = '${root.path}${Platform.pathSeparator}$name';
      RepoMeta.writeClone(
        clonePath,
        url: url,
        branch: GitSyncService.readHeadBranch(clonePath),
      );
      await _loadRepos();
      closeBusy();
    } on TimeoutException {
      closeBusy();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('克隆超时：请检查手机网络（Wi-Fi DNS / 移动数据）后重试'),
            duration: Duration(seconds: 6),
          ),
        );
      }
    } on SyncException catch (e) {
      closeBusy();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message == '已取消克隆' ? '已取消克隆' : '克隆失败: $e'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
      if (e.message == '已取消克隆') {
        // 孤儿 isolate 会在原生克隆自然返回后退出；在后台等它清理完
        // 半成品目录再刷新列表，不阻塞 UI（加号按钮由 finally 立即复位，
        // 重试克隆前 clone() 也会隐式等待清理完成）
        unawaited(
          () async {
            final root = await _reposRoot;
            await GitSyncService.waitForCleanup(
              '${root.path}${Platform.pathSeparator}$name',
            );
            if (mounted) await _loadRepos();
          }(),
        );
      }
    } on Exception catch (e) {
      closeBusy();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('克隆失败: $e')));
      }
    } finally {
      if (mounted) setState(() => _cloning = false);
    }
  }
}

/// 空状态引导。
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd, this.onAddLocal});

  final VoidCallback onAdd;

  /// 本地文件夹入口（可选：本地阅读器交付后出现）。
  final VoidCallback? onAddLocal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      children: [
        const SizedBox(height: 120),
        Icon(Icons.auto_stories_outlined,
            size: 72, color: theme.colorScheme.primary.withAlpha(120)),
        const SizedBox(height: 16),
        Center(
          child: Text('把你的仓库装进口袋',
              style: theme.textTheme.titleMedium),
        ),
        const SizedBox(height: 24),
        Center(
          child: FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            label: const Text('添加仓库'),
          ),
        ),
        if (onAddLocal != null) ...[
          const SizedBox(height: 12),
          Center(
            child: OutlinedButton.icon(
              onPressed: onAddLocal,
              icon: const Icon(Icons.folder_open),
              label: const Text('打开本地文件夹'),
            ),
          ),
        ],
      ],
    );
  }
}

/// 仓库卡片。
/// 相对时间文案（仓库卡「同步于 …」）。
String _relativeTime(DateTime time) {
  final diff = DateTime.now().difference(time);
  if (diff.inMinutes < 1) return '刚刚';
  if (diff.inHours < 1) return '${diff.inMinutes} 分钟前';
  if (diff.inDays < 1) return '${diff.inHours} 小时前';
  if (diff.inDays < 30) return '${diff.inDays} 天前';
  return '${time.year}-${time.month.toString().padLeft(2, '0')}-'
      '${time.day.toString().padLeft(2, '0')}';
}

class _RepoCard extends StatelessWidget {
  const _RepoCard({
    required this.name,
    required this.onTap,
    required this.onDelete,
    required this.pinned,
    required this.onTogglePin,
    this.source,
    this.lastOpened,
    this.syncedAt,
  });

  final String name;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  /// 是否已置顶（Roadmap「仓库管理·仓库置顶」）。
  final bool pinned;
  final VoidCallback onTogglePin;

  /// 远端来源（host + /owner/repo），未记录时为 null。
  final String? source;

  /// 最近打开的文件（仓库相对路径），未记录时为 null。
  final String? lastOpened;

  /// 最近一次成功同步时间，未记录时为 null。
  final DateTime? syncedAt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final last = lastOpened;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        onLongPress: onTogglePin,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(
                pinned
                    ? Icons.push_pin
                    : Icons.folder_special_outlined,
                color: pinned
                    ? const Color(0xFFF5B301)
                    : theme.colorScheme.primary,
                size: 32,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        style: theme.textTheme.titleMedium,
                        overflow: TextOverflow.ellipsis),
                    if (source != null && source!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(source!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ],
                    if (syncedAt != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        '同步于 ${_relativeTime(syncedAt!)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (last != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        '最近：$last',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                tooltip: pinned ? '取消置顶' : '置顶仓库',
                icon: Icon(
                  pinned ? Icons.push_pin : Icons.push_pin_outlined,
                  color: pinned ? const Color(0xFFF5B301) : null,
                ),
                onPressed: onTogglePin,
              ),
              IconButton(
                tooltip: '删除仓库',
                icon: const Icon(Icons.delete_outline),
                color: theme.colorScheme.outline,
                onPressed: onDelete,
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

/// 本地文件夹卡片（Roadmap「本地文件阅读器」）：打开/刷新/移除。
class _LocalCard extends StatelessWidget {
  const _LocalCard({
    required this.name,
    required this.onTap,
    required this.onRefresh,
    required this.onRemove,
  });

  final String name;
  final VoidCallback onTap;
  final VoidCallback onRefresh;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(
                Icons.folder_open,
                color: theme.colorScheme.tertiary,
                size: 32,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(name,
                    style: theme.textTheme.titleMedium,
                    overflow: TextOverflow.ellipsis),
              ),
              IconButton(
                tooltip: '刷新镜像',
                icon: const Icon(Icons.sync),
                onPressed: onRefresh,
              ),
              IconButton(
                tooltip: '移除',
                icon: const Icon(Icons.delete_outline),
                color: theme.colorScheme.outline,
                onPressed: onRemove,
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

/// 仓库内浏览页：保留仓库原目录结构逐层展开；搜索时全局扁平匹配。
