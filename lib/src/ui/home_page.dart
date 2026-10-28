import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

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
import 'code_viewer.dart';
import 'global_search_page.dart';
import 'image_gallery.dart';
import 'markdown_viewer.dart';
import 'search_snippet_text.dart';
import 'settings_page.dart';
import 'tag_page.dart';

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
        await sync.pull(repoDir: repo);
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

  void _openRepo(Directory repoDir) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => RepoPage(repoDir: repoDir),
        settings: const RouteSettings(name: 'repo-root'),
      ),
    );
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
    try {
      final sync = GitSyncService();
      for (final repo in repos) {
        try {
          final result = await sync.pull(repoDir: repo);
          if (result != PullResult.upToDate) updated++;
        } on Exception {
          failed++;
        }
      }
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
    return '${prefs.platform.webBase}/$owner/$repo.git';
  }

  /// 仓库地址匹配（剪贴板快速导入）：托管平台完整 URL。
  static final RegExp _repoUrlRegExp = RegExp(
    r'https?://(www\.)?(github\.com|gitee\.com|atomgit\.com|gitcode\.com)'
    r'/[\w.\-]+/[\w.\-]+',
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
      platform: _guessPlatform(url),
      owner: url.split('/').reversed.elementAt(1),
      name: name,
      cloneUrl: url,
      defaultBranch: 'main',
    );
    setState(() => _cloning = true);
    final rootNav = Navigator.of(context, rootNavigator: true);
    var busyClosed = false;
    void closeBusy() {
      if (busyClosed) return;
      busyClosed = true;
      rootNav.pop();
    }

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 24),
            Expanded(child: Text('正在克隆仓库…')),
          ],
        ),
      ),
    );
    try {
      await _sync.clone(
        repo: info,
        parentDir: await _reposRoot,
      );
      final root = await _reposRoot;
      RepoMeta.writeClone(
        '${root.path}${Platform.pathSeparator}$name',
        url: url,
        branch: info.defaultBranch,
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

  GitPlatform _guessPlatform(String url) {
    if (url.contains('github.com')) return GitPlatform.github;
    if (url.contains('gitee.com')) return GitPlatform.gitee;
    if (url.contains('atomgit.com')) return GitPlatform.atomgit;
    // gitcode.com 是 AtomGit 历史域名，两者均广泛使用，分别保留各自平台
    if (url.contains('gitcode.com')) return GitPlatform.gitcode;
    return GitPlatform.gitcode;
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
class _RepoCard extends StatelessWidget {
  const _RepoCard({
    required this.name,
    required this.onTap,
    required this.onDelete,
    required this.pinned,
    required this.onTogglePin,
    this.source,
    this.lastOpened,
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

  // 正文搜索（全文）：文件名搜索是同步过滤，正文搜索走后台 isolate + 防抖
  bool _contentMode = false;
  Timer? _searchDebounce;
  List<FileSearchResult>? _contentResults;
  bool _contentSearching = false;
  int _contentSeq = 0;

  /// 断链检查进行中（只读检查，不修改仓库）。
  bool _linkChecking = false;

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
    _scanNotes();
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

  /// 经典模式：当前目录下的 Markdown 笔记。
  List<NoteFile> _localNotes() {
    final prefix = widget.subPath.isEmpty ? '' : '${widget.subPath}/';
    return (_allNotes ?? const <NoteFile>[])
        .where((n) => n.relativePath.startsWith(prefix))
        .where((n) => !n.relativePath
            .substring(prefix.length)
            .contains('/'))
        .toList()
      ..sort((a, b) => compareNatural(a.fileName, b.fileName));
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
          .toList()
        ..sort((a, b) => compareNatural(a.fileName, b.fileName));

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
          // 深层目录一键弹回仓库根，免去逐级返回
          if (widget.subPath.isNotEmpty)
            IconButton(
              tooltip: '回到根目录',
              icon: const Icon(Icons.home_outlined),
              onPressed: () => Navigator.popUntil(
                context,
                (route) =>
                    route.settings.name == 'repo-root' || route.isFirst,
              ),
            ),
          IconButton(
            onPressed: _pull,
            icon: const Icon(Icons.sync),
            tooltip: '同步',
          ),
          PopupMenuButton<String>(
            tooltip: '更多',
            onSelected: (value) {
              if (value == 'links') _checkLinks();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'links', child: Text('检查断链')),
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
  void _openByRelativePath(String relativePath) {
    for (final note in _allNotes ?? const <NoteFile>[]) {
      if (note.relativePath == relativePath) {
        _openFile(note);
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

  void _openFile(NoteFile note) {
    RepoMeta.touchLastOpened(widget.repoDir.path, note.relativePath);
    if (note.isMarkdown || note.isPlainText) {
      Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => MarkdownViewerPage(
            note: note,
            repoRoot: widget.repoDir.path,
          ),
        ),
      );
    } else if (note.isImage) {
      Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => ImageGalleryPage(
            sources: [note.absolutePath],
            baseDir: widget.repoDir.path,
          ),
        ),
      );
    } else {
      Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => CodeViewerPage(
            path: note.absolutePath,
            fileName: note.fileName + note.extension,
          ),
        ),
      );
    }
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
      final result = await GitSyncService().pull(
        repoDir: widget.repoDir,
      );
      await _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result == PullResult.upToDate ? '已是最新' : '已更新'),
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } on Exception catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('同步失败: $e')));
      }
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
