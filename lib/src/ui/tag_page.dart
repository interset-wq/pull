import 'dart:io';

import 'package:flutter/material.dart';

import '../notes/note_scanner.dart';
import '../notes/tag_index.dart';
import '../theme/app_prefs.dart';
import 'markdown_viewer.dart';

/// 标签页：聚合所有仓库（含本地文件夹镜像）front-matter 里的 tags，
/// 点标签按 AND 过滤，结果跨仓库分组展示。
class TagPage extends StatefulWidget {
  const TagPage({required this.roots, super.key});

  final List<Directory> roots;

  @override
  State<TagPage> createState() => _TagPageState();
}

class _TagPageState extends State<TagPage> {
  List<TaggedFile>? _files;
  String? _error;
  final Set<String> _selected = <String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = AppPrefs.instance;
    try {
      final files = await TagIndex.scan(
        widget.roots,
        useDefaults: prefs?.ignoreDefaults ?? true,
        customRules: prefs?.ignoreRules ?? const [],
      );
      if (!mounted) return;
      setState(() => _files = files);
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    }
  }

  /// 标签 → 出现次数（按文件计），次数多的在前。
  List<MapEntry<String, int>> get _tagCounts {
    final counts = <String, int>{};
    for (final file in _files ?? const <TaggedFile>[]) {
      for (final tag in file.tags) {
        counts[tag] = (counts[tag] ?? 0) + 1;
      }
    }
    final entries = counts.entries.toList()
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        return byCount != 0 ? byCount : a.key.compareTo(b.key);
      });
    return entries;
  }

  List<TaggedFile> get _filtered {
    final files = _files ?? const <TaggedFile>[];
    if (_selected.isEmpty) return files;
    return files
        .where((f) => _selected.every(f.tags.contains))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('标签'),
        actions: [
          if (_selected.isNotEmpty)
            TextButton(
              onPressed: () => setState(_selected.clear),
              child: const Text('清除筛选'),
            ),
        ],
      ),
      body: _buildBody(theme),
    );
  }

  Widget _buildBody(ThemeData theme) {
    final error = _error;
    if (error != null) {
      return Center(child: Padding(padding: const EdgeInsets.all(32), child: Text('标签读取失败：$error')));
    }
    final files = _files;
    if (files == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final counts = _tagCounts;
    if (counts.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            '笔记的 front-matter 里没有 tags',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }
    final filtered = _filtered;
    final children = <Widget>[
      Text(
        '共 ${files.length} 篇带标签的笔记',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          for (final entry in counts)
            FilterChip(
              label: Text('${entry.key} ${entry.value}'),
              selected: _selected.contains(entry.key),
              onSelected: (on) => setState(() {
                if (on) {
                  _selected.add(entry.key);
                } else {
                  _selected.remove(entry.key);
                }
              }),
            ),
        ],
      ),
      const Divider(height: 24),
      if (filtered.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Center(
            child: Text(
              '没有同时包含所选标签的笔记',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
    ];
    String? lastRepo;
    for (final file in filtered) {
      if (file.repoName != lastRepo) {
        lastRepo = file.repoName;
        children.add(
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: Text(
              file.repoName,
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ),
        );
      }
      children.add(
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.description_outlined, size: 20),
          title: Text(
            file.relativePath.split('/').last,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            '${file.relativePath} · ${file.tags.map((t) => '#$t').join(' ')}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          onTap: () => _open(file),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: children,
    );
  }

  void _open(TaggedFile tagged) {
    final file = File(
      '${tagged.repoRoot}${Platform.pathSeparator}'
      '${tagged.relativePath.replaceAll('/', Platform.pathSeparator)}',
    );
    if (!file.existsSync()) return;
    final stat = file.statSync();
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => MarkdownViewerPage(
          note: NoteFile(
            relativePath: tagged.relativePath,
            absolutePath: file.path,
            modified: stat.modified,
            sizeBytes: stat.size,
          ),
          repoRoot: tagged.repoRoot,
        ),
      ),
    );
  }
}
