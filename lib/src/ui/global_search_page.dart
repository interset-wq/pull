import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../notes/note_scanner.dart';
import '../search/repo_search.dart';
import '../search/text_search.dart';
import '../theme/app_prefs.dart';
import 'markdown_viewer.dart';
import 'search_snippet_text.dart';

/// 跨仓库搜索页：逐个仓库检索、结果按仓库分组流式出现。
///
/// 单个仓库的检索由 [RepoSearchService] 在 isolate 内完成；这里顺序遍历
/// 选中的仓库，避免同时开一堆 isolate 抢 CPU。
/// 支持搜索历史（本地持久化）、按仓库过滤、「仅标题 / 仅正文」两种模式。
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
  bool _titleOnly = false;
  int _seq = 0;
  List<_GlobalHit> _hits = const [];

  /// 选中的仓库名集合；空 = 全部仓库。
  Set<String> _selectedRepos = {};

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

  /// 条件变化（模式切换 / 仓库过滤）后重跑当前查询；查询太短直接忽略。
  void _scheduleRun([int delayMs = 200]) {
    if (_query.length < 2) return;
    _debounce?.cancel();
    setState(() => _searching = true);
    _debounce = Timer(Duration(milliseconds: delayMs), () => _run(_query));
  }

  /// 仓库在当前过滤范围（全部 / 勾选集合）内才参与检索。
  bool _inScope(Directory repo) {
    if (_selectedRepos.isEmpty) return true;
    return _selectedRepos.contains(_repoName(repo));
  }

  String _repoName(Directory repo) =>
      repo.path.split(Platform.pathSeparator).last;

  Future<void> _run(String query) async {
    final seq = ++_seq;
    unawaited(AppPrefs.instance?.addSearchHistory(query));
    final merged = <_GlobalHit>[];
    for (final repo in widget.repos) {
      if (!_inScope(repo)) continue;
      if (!mounted || seq != _seq) return;
      List<FileSearchResult> hits;
      try {
        hits = await RepoSearchService.search(
          repoRoot: repo.path,
          query: query,
          titleOnly: _titleOnly,
        );
      } on Object {
        hits = const [];
      }
      if (!mounted || seq != _seq) return;
      merged.addAll([
        for (final hit in hits)
          _GlobalHit(repo: repo, repoName: _repoName(repo), result: hit),
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
          decoration: InputDecoration(
            border: InputBorder.none,
            hintText: _titleOnly ? '按文件名搜索全部仓库' : '搜索全部仓库的正文',
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
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Row(
              children: [
                // 「仅标题 / 仅正文」模式切换
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('正文')),
                    ButtonSegment(value: true, label: Text('仅标题')),
                  ],
                  selected: {_titleOnly},
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onSelectionChanged: (selection) {
                    setState(() {
                      _titleOnly = selection.first;
                      _hits = const [];
                    });
                    _scheduleRun();
                  },
                ),
                const SizedBox(width: 8),
                Expanded(child: _repoFilterChips(theme)),
              ],
            ),
          ),
        ),
      ),
      body: _buildBody(theme),
    );
  }

  /// 仓库过滤：横向滚动的筛选标签，未选任何仓库 = 搜全部。
  Widget _repoFilterChips(ThemeData theme) {
    if (widget.repos.length < 2) return const SizedBox.shrink();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          FilterChip(
            label: const Text('全部'),
            selected: _selectedRepos.isEmpty,
            showCheckmark: false,
            visualDensity: VisualDensity.compact,
            onSelected: (_) {
              setState(() => _selectedRepos = {});
              _scheduleRun();
            },
          ),
          for (final repo in widget.repos)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: FilterChip(
                label: Text(_repoName(repo)),
                selected: _selectedRepos.contains(_repoName(repo)),
                showCheckmark: false,
                visualDensity: VisualDensity.compact,
                onSelected: (selected) {
                  setState(() {
                    final next = Set.of(_selectedRepos);
                    selected
                        ? next.add(_repoName(repo))
                        : next.remove(_repoName(repo));
                    _selectedRepos = next;
                  });
                  // 改过滤条件立即重跑，否则要再改一次查询才生效
                  _scheduleRun();
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_query.length < 2) {
      final history = AppPrefs.instance?.searchHistory ?? const <String>[];
      if (history.isEmpty) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
              widget.repos.isEmpty
                  ? '还没有克隆任何仓库'
                  : '在 ${widget.repos.length} 个仓库中搜索（至少 2 个字符）',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        );
      }
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Text(
            '搜索历史',
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final item in history)
                InputChip(
                  label: Text(item),
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    _controller.text = item;
                    _onChanged(item);
                  },
                  onDeleted: () =>
                      AppPrefs.instance?.removeSearchHistory(item),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '点击历史词直接搜索，长按 ✕ 删除',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      );
    }
    if (_hits.isEmpty) {
      return Center(
        child: _searching
            ? const CircularProgressIndicator()
            : Text(
                _titleOnly ? '没有匹配的文件名' : '没有匹配的正文',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
      );
    }
    final visible = _hits
        .where((hit) => _selectedRepos.isEmpty ||
            _selectedRepos.contains(hit.repoName))
        .toList();
    final items = <Widget>[];
    String? lastRepo;
    for (final hit in visible) {
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
          if (!_titleOnly)
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
          // 带着检索词进阅读页：自动打开查找条并定位到第一处命中（仅标题模式没有正文命中，不带）
          initialFindQuery: _titleOnly ? null : _query,
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
