import 'dart:io';

import 'package:flutter/material.dart';

import '../git/repo_meta.dart';
import '../notes/note_scanner.dart';
import 'open_note.dart';

/// 更新收件箱：把各仓库/本地镜像里「上次拉取后新增或修改、且尚未打开」的
/// 文件聚到一页，点击即读并清除该条标记。
///
/// 数据来自 `RepoMeta.recentChanges`（pull 时写入、打开文件时清除），
/// 不额外维护索引，也不改动仓库内容。
class UpdatesPage extends StatefulWidget {
  const UpdatesPage({required this.sources, super.key});

  /// 来源：仓库目录或本地镜像目录；name 用于分组标题。
  final List<({String name, Directory root})> sources;

  @override
  State<UpdatesPage> createState() => _UpdatesPageState();
}

class _UpdateGroup {
  _UpdateGroup(this.name, this.root, this.changes);

  final String name;
  final Directory root;

  /// 相对路径 → 'a'（新增）/ 'm'（修改）。
  final Map<String, String> changes;
}

class _UpdatesPageState extends State<UpdatesPage> {
  List<_UpdateGroup> _groups = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final groups = <_UpdateGroup>[];
    for (final source in widget.sources) {
      final changes = RepoMeta.readRecentChanges(source.root.path);
      if (changes.isEmpty) continue;
      groups.add(_UpdateGroup(source.name, source.root, Map.of(changes)));
    }
    if (!mounted) return;
    setState(() {
      _groups = groups;
      _loading = false;
    });
  }

  int get _total =>
      _groups.fold(0, (sum, group) => sum + group.changes.length);

  void _markAllRead() {
    for (final group in _groups) {
      RepoMeta.clearRecentChanges(group.root.path);
    }
    setState(() => _groups = const []);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已全部标记为已读')),
    );
  }

  Future<void> _open(_UpdateGroup group, String relativePath) async {
    final file = File(
      '${group.root.path}${Platform.pathSeparator}'
      '${relativePath.replaceAll('/', Platform.pathSeparator)}',
    );
    if (!file.existsSync()) {
      RepoMeta.clearRecentChange(group.root.path, relativePath);
      if (!mounted) return;
      setState(() => _drop(group, relativePath));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('文件已不存在，已清除该标记')),
      );
      return;
    }
    final stat = file.statSync();
    await openNoteFile(
      context,
      repoRoot: group.root.path,
      note: NoteFile(
        relativePath: relativePath,
        absolutePath: file.path,
        modified: stat.modified,
        sizeBytes: stat.size,
      ),
    );
    if (!mounted) return;
    // 打开即清除；收件箱本身回到前台时把这一条移掉
    setState(() => _drop(group, relativePath));
  }

  void _drop(_UpdateGroup group, String relativePath) {
    group.changes.remove(relativePath);
    _groups = _groups.where((g) => g.changes.isNotEmpty).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('更新收件箱'),
        actions: [
          if (_total > 0)
            TextButton(
              onPressed: _markAllRead,
              child: const Text('全部已读'),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _groups.isEmpty
              ? _emptyState(theme)
              : ListView.builder(
                  itemCount: _rows.length,
                  itemBuilder: (context, i) => _rows[i],
                ),
    );
  }

  List<Widget> get _rows {
    final theme = Theme.of(context);
    final rows = <Widget>[];
    for (final group in _groups) {
      rows.add(_groupHeader(group, theme));
      final paths = group.changes.keys.toList()..sort(compareNatural);
      for (final path in paths) {
        rows.add(_noteRow(group, path, theme));
      }
    }
    return rows;
  }

  Widget _groupHeader(_UpdateGroup group, ThemeData theme) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Row(
          children: [
            Expanded(
              child: Text(
                group.name,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              '${group.changes.length}',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );

  Widget _noteRow(_UpdateGroup group, String relativePath, ThemeData theme) {
    final name = relativePath.split('/').last;
    final slash = relativePath.lastIndexOf('/');
    final dir = slash < 0 ? '' : relativePath.substring(0, slash);
    final added = group.changes[relativePath] == 'a';
    return ListTile(
      dense: true,
      leading: Icon(
        _iconFor(relativePath),
        size: 20,
        color: theme.colorScheme.primary,
      ),
      title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: dir.isEmpty
          ? null
          : Text(dir, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: theme.colorScheme.primary.withAlpha(30),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          added ? '新增' : '更新',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.primary,
          ),
        ),
      ),
      onTap: () => _open(group, relativePath),
    );
  }

  static IconData _iconFor(String relativePath) {
    final lower = relativePath.toLowerCase();
    if (lower.endsWith('.ipynb')) return Icons.science_outlined;
    if (lower.endsWith('.md') ||
        lower.endsWith('.markdown') ||
        lower.endsWith('.mdx')) {
      return Icons.article_outlined;
    }
    if (lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.svg')) {
      return Icons.image_outlined;
    }
    return Icons.code;
  }

  Widget _emptyState(ThemeData theme) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.mark_email_read_outlined,
                size: 48,
                color: theme.colorScheme.outline,
              ),
              const SizedBox(height: 12),
              Text('没有未读的更新', style: theme.textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(
                '在仓库里拉取更新后，新增和修改的笔记会出现在这里。',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
}
