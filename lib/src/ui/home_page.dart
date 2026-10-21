import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../git/sync_service.dart';
import '../notes/note_scanner.dart';
import '../platforms/git_platform.dart';
import '../platforms/repo_info.dart';
import 'markdown_viewer.dart';

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
                      itemCount: repos.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (context, i) {
                        final repo = repos[i];
                        final name =
                            repo.path.split(Platform.pathSeparator).last;
                        final count =
                            NoteScanner().scan(repo.path).length;
                        return _RepoCard(
                          name: name,
                          noteCount: count,
                          onTap: () => _openRepo(repo),
                        );
                      },
                    ),
            ),
    );
  }

  void _openRepo(Directory repoDir) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => RepoPage(repoDir: repoDir)),
    );
  }

  Future<void> _showCloneDialog() async {
    final urlCtrl = TextEditingController();
    final tokenCtrl = TextEditingController();
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
              decoration: const InputDecoration(
                labelText: '仓库地址',
                hintText: 'https://…/notes.git',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: tokenCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: '访问 Token',
                hintText: '私有仓库必填，公开仓库可留空',
                border: OutlineInputBorder(),
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

    final url = urlCtrl.text.trim();
    if (url.isEmpty) return;
    final name = url.split('/').last.replaceAll('.git', '');
    final info = RepoInfo(
      platform: _guessPlatform(url),
      owner: url.split('/').reversed.elementAt(1),
      name: name,
      cloneUrl: url,
      defaultBranch: 'main',
    );
    setState(() => _cloning = true);
    try {
      await _sync.clone(
        repo: info,
        parentDir: await _reposRoot,
        token: tokenCtrl.text.trim(),
      );
      await _loadRepos();
    } on Exception catch (e) {
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
          child: Text('把你的笔记仓库装进口袋',
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
  const _RepoCard({required this.name, required this.noteCount, required this.onTap});

  final String name;
  final int noteCount;
  final VoidCallback onTap;

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
                    const SizedBox(height: 4),
                    Text('$noteCount 篇笔记',
                        style: theme.textTheme.bodySmall),
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
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
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
      ..sort((a, b) =>
          a.fileName.toLowerCase().compareTo(b.fileName.toLowerCase()));
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
              hintText: searching ? '搜索中…' : '搜索笔记',
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
              onRefresh: () async => _refresh(),
              child: isEmpty
                  ? ListView(children: const [
                      SizedBox(height: 120),
                      Center(child: Text('这里没有笔记')),
                    ])
                  : ListView(
                      padding: const EdgeInsets.only(bottom: 32),
                      children: [
                        // 子文件夹（保持原目录结构）
                        for (final name in dirs)
                          ListTile(
                            leading: Icon(
                              Icons.folder_outlined,
                              color: theme.colorScheme.primary,
                            ),
                            title: Text(name),
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
                        // 当前目录下的笔记
                        for (final note in notes)
                          ListTile(
                            leading: const Icon(Icons.description_outlined),
                            title: Text(
                              note.fileName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: searching
                                ? Text(
                                    note.relativePath,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  )
                                : Text(_fmtTime(note.modified)),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute<void>(
                                builder: (_) => MarkdownViewerPage(
                                  note: note,
                                  repoRoot: widget.repoDir.path,
                                ),
                              ),
                            ),
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

  String _fmtTime(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return '刚刚';
    if (d.inHours < 1) return '${d.inMinutes} 分钟前';
    if (d.inDays < 1) return '${d.inHours} 小时前';
    if (d.inDays < 30) return '${d.inDays} 天前';
    return '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
  }

  Future<void> _pull() async {
    try {
      final result = await GitSyncService().pull(
        repoDir: widget.repoDir,
        token: '', // V1：公开仓库
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
