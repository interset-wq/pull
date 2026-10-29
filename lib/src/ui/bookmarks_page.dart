import 'dart:io';

import 'package:flutter/material.dart';

import '../git/repo_meta.dart';
import '../notes/note_scanner.dart';
import 'open_note.dart';

/// 书签来源：一个仓库或本地镜像目录。
class BookmarkSource {
  const BookmarkSource({required this.name, required this.root});

  final String name;
  final Directory root;
}

/// 跨仓库书签页：按来源分组列出所有段落级书签，点击直达，可删除。
///
/// 书签存于各仓库的本地 meta（`<reposRoot>/.meta/<仓库名>.json`），
/// 不改动仓库内容；删除仓库时随 meta 一并清掉。
class BookmarksPage extends StatefulWidget {
  const BookmarksPage({required this.sources, super.key});

  final List<BookmarkSource> sources;

  @override
  State<BookmarksPage> createState() => _BookmarksPageState();
}

class _BookmarkGroup {
  _BookmarkGroup(this.name, this.root, this.items);

  final String name;
  final Directory root;
  final List<Bookmark> items;
}

class _BookmarksPageState extends State<BookmarksPage> {
  List<_BookmarkGroup> _groups = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final groups = <_BookmarkGroup>[];
    for (final source in widget.sources) {
      final items = RepoMeta.readBookmarks(source.root.path);
      if (items.isEmpty) continue;
      groups.add(_BookmarkGroup(source.name, source.root, items));
    }
    if (!mounted) return;
    setState(() {
      _groups = groups;
      _loading = false;
    });
  }

  int get _total => _groups.fold(0, (sum, group) => sum + group.items.length);

  Future<void> _open(_BookmarkGroup group, Bookmark bookmark) async {
    final file = File(
      '${group.root.path}${Platform.pathSeparator}'
      '${bookmark.relativePath.replaceAll('/', Platform.pathSeparator)}',
    );
    if (!file.existsSync()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('文件已不存在，可点右侧删除这条书签')),
      );
      return;
    }
    final stat = file.statSync();
    await openNoteFile(
      context,
      repoRoot: group.root.path,
      note: NoteFile(
        relativePath: bookmark.relativePath,
        absolutePath: file.path,
        modified: stat.modified,
        sizeBytes: stat.size,
      ),
      initialFraction: bookmark.fraction,
    );
  }

  void _delete(_BookmarkGroup group, Bookmark bookmark) {
    RepoMeta.removeBookmark(group.root.path, bookmark);
    setState(() {
      group.items.removeWhere((b) =>
          b.relativePath == bookmark.relativePath &&
          b.createdAt == bookmark.createdAt);
      _groups = _groups.where((g) => g.items.isNotEmpty).toList();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已删除书签'), duration: Duration(seconds: 1)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(_total > 0 ? '书签（$_total）' : '书签'),
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
      rows.add(
        Padding(
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
                '${group.items.length}',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
      for (final bookmark in group.items) {
        rows.add(_row(group, bookmark, theme));
      }
    }
    return rows;
  }

  Widget _row(_BookmarkGroup group, Bookmark bookmark, ThemeData theme) {
    final fileName = bookmark.relativePath.split('/').last;
    return ListTile(
      dense: true,
      leading: Icon(
        Icons.bookmark_outline,
        size: 20,
        color: theme.colorScheme.primary,
      ),
      title: Text(
        bookmark.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '$fileName · ${(bookmark.fraction * 100).round()}%',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: IconButton(
        tooltip: '删除书签',
        icon: const Icon(Icons.delete_outline, size: 20),
        onPressed: () => _delete(group, bookmark),
      ),
      onTap: () => _open(group, bookmark),
    );
  }

  Widget _emptyState(ThemeData theme) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.bookmark_border,
                size: 48,
                color: theme.colorScheme.outline,
              ),
              const SizedBox(height: 12),
              Text('还没有书签', style: theme.textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(
                '在阅读页菜单里点「在此处加书签」，就会出现在这里。',
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
