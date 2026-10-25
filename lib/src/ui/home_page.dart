import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../git/repo_meta.dart';
import '../git/sync_service.dart';
import '../notes/note_scanner.dart';
import '../platforms/git_platform.dart';
import '../platforms/repo_info.dart';
import '../theme/app_prefs.dart';
import 'code_viewer.dart';
import 'image_gallery.dart';
import 'markdown_viewer.dart';
import 'settings_page.dart';

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
    _silentPullAll();
  }

  /// 启动时后台静默更新所有仓库：不转圈、不弹提示，完成后仅刷新列表。
  Future<void> _silentPullAll() async {
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

  Future<void> _loadRepos() async {
    final root = await _reposRoot;
    if (!mounted) return;
    setState(() {
      _repos = root
          .listSync(followLinks: false)
          .whereType<Directory>()
          .where((d) => Directory('${d.path}${Platform.pathSeparator}.git')
              .existsSync())
          .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final repos = _repos;
    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        title: Text('Reader', style: theme.textTheme.headlineMedium),
        actions: [
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
      body: repos == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadRepos,
              child: repos.isEmpty
                  ? _EmptyState(onAdd: _showCloneDialog)
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                      itemCount: repos.length + 1,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (context, i) {
                        if (i == 0) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
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
                            ],
                          );
                        }
                        final repo = repos[i - 1];
                        final name =
                            repo.path.split(Platform.pathSeparator).last;
                        final meta = RepoMeta.read(repo.path);
                        return _RepoCard(
                          name: name,
                          source: meta?.source,
                          lastOpened: meta?.lastOpened,
                          onTap: () => _openRepo(repo),
                          onDelete: () => _confirmDelete(repo),
                        );
                      },
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
    );
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
  const _EmptyState({required this.onAdd});

  final VoidCallback onAdd;

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
    this.source,
    this.lastOpened,
  });

  final String name;
  final VoidCallback onTap;
  final VoidCallback onDelete;

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
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.folder_special_outlined,
                  color: theme.colorScheme.primary, size: 32),
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
  final _scanner = NoteScanner();
  List<NoteFile>? _allNotes;
  String _query = '';

  Directory get _currentDir => Directory(
      '${widget.repoDir.path}${Platform.pathSeparator}'
      '${widget.subPath.replaceAll('/', Platform.pathSeparator)}'
          .replaceAll(RegExp(r'[/\\]+$'), ''));

  @override
  void initState() {
    super.initState();
    _allNotes = _scanner.scan(widget.repoDir.path);
  }

  void _refresh() {
    setState(() => _allNotes = _scanner.scan(widget.repoDir.path));
  }

  /// 当前目录下的子文件夹（跳过隐藏与临时目录），排序后返回名称。
  List<String> _subDirs() {
    if (!mounted) return const [];
    final dir = _currentDir;
    if (!dir.existsSync()) return const [];
    return dir
        .listSync(followLinks: false)
        .whereType<Directory>()
        .map((d) => d.path.split(Platform.pathSeparator).last)
        .where((name) =>
            !name.startsWith('.') && !NoteScanner.skipDirs.contains(name))
        .toList()
      ..sort(compareNatural);
  }

  /// 当前目录下的 Markdown 笔记。
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final searching = _query.isNotEmpty;
    final repoName = widget.repoDir.path.split(Platform.pathSeparator).last;
    final title = widget.subPath.isEmpty
        ? repoName
        : widget.subPath.split('/').last;

    final notes = searching ? _searchAll() : _localNotes();
    final dirs = searching ? const <String>[] : _subDirs();
    final isEmpty = dirs.isEmpty && notes.isEmpty;

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
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: SearchBar(
              hintText: searching ? '搜索中…' : '搜索文件',
              leading: const Icon(Icons.search),
              elevation: const WidgetStatePropertyAll(0),
              constraints: const BoxConstraints(minHeight: 44),
              trailing: searching
                  ? [
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(() => _query = ''),
                      ),
                    ]
                  : null,
              onChanged: (v) => setState(() => _query = v.toLowerCase()),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _pull,
              child: isEmpty
                  ? ListView(children: const [
                      SizedBox(height: 120),
                      Center(child: Text('这里没有文件')),
                    ])
                  : ListView(
                      padding: const EdgeInsets.only(bottom: 32),
                      children: [
                        // 子文件夹（保持原目录结构），尾部显示文件数
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
                        // 当前目录下的笔记与代码文件（单行紧凑）
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
                            subtitle: searching
                                ? Text(
                                    note.relativePath,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme
                                          .onSurfaceVariant,
                                    ),
                                  )
                                : null,
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
    if (note.isMarkdown) {
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
    try {
      final result = await GitSyncService().pull(
        repoDir: widget.repoDir,
      );
      _refresh();
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
