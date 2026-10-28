import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../notes/note_scanner.dart';
import '../search/repo_search.dart';
import '../search/text_search.dart';
import 'markdown_viewer.dart';
import 'search_snippet_text.dart';

/// 跨仓库正文搜索页：逐个仓库检索、结果按仓库分组流式出现。
///
/// 单个仓库的检索由 [RepoSearchService] 在 isolate 内完成；这里顺序遍历
/// 所有仓库，避免同时开一堆 isolate 抢 CPU。
class GlobalSearchPage extends StatefulWidget {
  const GlobalSearchPage({required this.repos, super.key});

  final List<Directory> repos;

  @override
  State<GlobalSearchPage> createState() => _GlobalSearchPageState();
}

class _GlobalSearchPageState extends State<GlobalSearchPage> {
  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;
  String _query = '';
  bool _searching = false;
  int _seq = 0;
  List<_GlobalHit> _hits = const [];

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    final q = value.trim();
    setState(() {
      _query = q;
      _hits = const [];
    });
    if (q.length < 2) {
      setState(() => _searching = false);
      return;
    }
    setState(() => _searching = true);
    _debounce = Timer(const Duration(milliseconds: 400), () => _run(q));
  }

  Future<void> _run(String query) async {
    final seq = ++_seq;
    final merged = <_GlobalHit>[];
    for (final repo in widget.repos) {
      if (!mounted || seq != _seq) return;
      List<FileSearchResult> hits;
      try {
        hits = await RepoSearchService.search(
          repoRoot: repo.path,
          query: query,
        );
      } on Object {
        hits = const [];
      }
      if (!mounted || seq != _seq) return;
      final repoName = repo.path.split(Platform.pathSeparator).last;
      merged.addAll([
        for (final hit in hits)
          _GlobalHit(repo: repo, repoName: repoName, result: hit),
      ]);
      // 逐仓库更新：先搜完的仓库先出结果，不必等全部结束
      setState(() => _hits = List.of(merged));
    }
    if (mounted && seq == _seq) setState(() => _searching = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            border: InputBorder.none,
            hintText: '搜索全部仓库的正文',
          ),
          onChanged: _onChanged,
        ),
        actions: [
          if (_controller.text.isNotEmpty)
            IconButton(
              tooltip: '清空',
              icon: const Icon(Icons.close),
              onPressed: () {
                _controller.clear();
                _onChanged('');
              },
            ),
        ],
      ),
      body: _buildBody(theme),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_query.length < 2) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            widget.repos.isEmpty
                ? '还没有克隆任何仓库'
                : '在 ${widget.repos.length} 个仓库的正文中搜索（至少 2 个字符）',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }
    if (_hits.isEmpty) {
      return Center(
        child: _searching
            ? const CircularProgressIndicator()
            : Text(
                '没有匹配的正文',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
      );
    }
    final items = <Widget>[];
    String? lastRepo;
    for (final hit in _hits) {
      if (hit.repoName != lastRepo) {
        lastRepo = hit.repoName;
        items.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              hit.repoName,
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ),
        );
      }
      items.add(_hitTile(theme, hit));
    }
    if (_searching) {
      items.add(
        const Padding(
          padding: EdgeInsets.all(16),
          child: Center(
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
      );
    }
    return ListView(padding: const EdgeInsets.only(bottom: 32), children: items);
  }

  Widget _hitTile(ThemeData theme, _GlobalHit hit) {
    final result = hit.result;
    return ListTile(
      title: Row(
        children: [
          Expanded(
            child: Text(
              result.relativePath.split('/').last,
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
      onTap: () => _openHit(hit),
    );
  }

  void _openHit(_GlobalHit hit) {
    final relPath = hit.result.relativePath;
    final file = File(
      '${hit.repo.path}${Platform.pathSeparator}'
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
          repoRoot: hit.repo.path,
          // 带着检索词进阅读页：自动打开查找条并定位到第一处命中
          initialFindQuery: _query,
        ),
      ),
    );
  }
}

class _GlobalHit {
  const _GlobalHit({
    required this.repo,
    required this.repoName,
    required this.result,
  });

  final Directory repo;
  final String repoName;
  final FileSearchResult result;
}
