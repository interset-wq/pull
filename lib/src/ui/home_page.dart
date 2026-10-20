import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../git/sync_service.dart';
import '../notes/note_scanner.dart';
import '../platforms/git_platform.dart';
import '../platforms/repo_info.dart';
import 'markdown_viewer.dart';

/// 首页：已克隆仓库列表 + 添加仓库（克隆）。
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _sync = GitSyncService();
  final _scanner = NoteScanner();
  List<Directory>? _repos;

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
    final repos = _repos;
    return Scaffold(
      appBar: AppBar(title: const Text('Reader')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCloneDialog,
        icon: const Icon(Icons.add),
        label: const Text('添加仓库'),
      ),
      body: repos == null
          ? const Center(child: CircularProgressIndicator())
          : repos.isEmpty
              ? const Center(child: Text('还没有仓库，点右下角添加'))
              : ListView(
                  children: [
                    for (final repo in repos)
                      ListTile(
                        leading: const Icon(Icons.folder_special_outlined),
                        title: Text(repo.path.split(Platform.pathSeparator).last),
                        onTap: () => _openRepo(repo),
                      ),
                  ],
                ),
    );
  }

  void _openRepo(Directory repoDir) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => RepoPage(repoDir: repoDir, scanner: _scanner),
      ),
    );
  }

  Future<void> _showCloneDialog() async {
    final urlCtrl = TextEditingController();
    final tokenCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('克隆仓库'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: urlCtrl,
              decoration: const InputDecoration(
                labelText: '仓库地址（https 结尾 .git）',
              ),
            ),
            TextField(
              controller: tokenCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: '访问 Token（公开仓库可留空）',
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
    try {
      await _sync.clone(
        repo: info,
        parentDir: await _reposRoot,
        token: tokenCtrl.text.trim(),
      );
      await _loadRepos();
    } on SyncException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('克隆失败: $e')));
      }
    }
  }

  GitPlatform _guessPlatform(String url) {
    if (url.contains('github.com')) return GitPlatform.github;
    if (url.contains('gitee.com')) return GitPlatform.gitee;
    return GitPlatform.gitcode;
  }
}

/// 仓库内笔记列表页。
class RepoPage extends StatefulWidget {
  const RepoPage({required this.repoDir, required this.scanner, super.key});

  final Directory repoDir;
  final NoteScanner scanner;

  @override
  State<RepoPage> createState() => _RepoPageState();
}

class _RepoPageState extends State<RepoPage> {
  List<NoteFile>? _notes;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _notes = widget.scanner.scan(widget.repoDir.path);
  }

  @override
  Widget build(BuildContext context) {
    final notes = _notes!;
    final filtered = _query.isEmpty
        ? notes
        : notes
            .where((n) =>
                n.fileName.toLowerCase().contains(_query) ||
                n.relativePath.toLowerCase().contains(_query))
            .toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.repoDir.path.split(Platform.pathSeparator).last),
        actions: [
          IconButton(
            onPressed: _pull,
            icon: const Icon(Icons.sync),
            tooltip: '同步（pull）',
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              decoration: const InputDecoration(
                hintText: '按文件名/路径搜索',
                isDense: true,
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (v) => setState(() => _query = v.toLowerCase()),
            ),
          ),
        ),
      ),
      body: filtered.isEmpty
          ? const Center(child: Text('没有找到笔记'))
          : ListView.builder(
              itemCount: filtered.length,
              itemBuilder: (context, i) {
                final note = filtered[i];
                return ListTile(
                  title: Text(note.fileName),
                  subtitle: Text(note.relativePath),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => MarkdownViewerPage(
                        note: note,
                        repoRoot: widget.repoDir.path,
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }

  Future<void> _pull() async {
    try {
      final result = await GitSyncService().pull(
        repoDir: widget.repoDir,
        token: '', // V1：公开仓库
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result == PullResult.upToDate ? '已是最新' : '已更新')),
        );
      }
    } on SyncException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('同步失败: $e')));
      }
    }
  }
}
