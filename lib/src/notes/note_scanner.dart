import 'dart:io';

/// 扫描本地仓库中的笔记（Markdown/Notebook）与代码文件。
class NoteScanner {
  static const mdExtensions = {'.md', '.markdown', '.ipynb'};

  /// 支持语法高亮查看的代码/文本扩展名。
  static const codeExtensions = {
    '.dart', '.py', '.js', '.mjs', '.ts', '.tsx', '.jsx', '.java', '.kt',
    '.kts', '.go', '.rs', '.c', '.h', '.cpp', '.cc', '.hpp', '.cs', '.rb',
    '.php', '.swift', '.m', '.sh', '.bash', '.zsh', '.json', '.yaml', '.yml',
    '.toml', '.xml', '.html', '.css', '.scss', '.sql', '.r', '.lua', '.pl',
    '.txt', '.gradle', '.properties', '.cfg', '.ini', '.cmake',
  };
  static const skipDirs = {'.git', 'node_modules', '.obsidian', 'temp'};

  /// 递归列出仓库下所有可查看文件（相对仓库根的路径），
  /// 按最后修改时间倒序。
  List<NoteFile> scan(String repoRoot) {
    final root = Directory(repoRoot);
    if (!root.existsSync()) return [];
    final notes = <NoteFile>[];
    _walk(root, root, notes);
    notes.sort((a, b) => b.modified.compareTo(a.modified));
    return notes;
  }

  void _walk(Directory dir, Directory root, List<NoteFile> out) {
    for (final entity in dir.listSync(followLinks: false)) {
      final name = entity.path.split(Platform.pathSeparator).last;
      if (entity is Directory) {
        if (skipDirs.contains(name) || name.startsWith('.')) continue;
        _walk(entity, root, out);
      } else if (entity is File) {
        final ext = name.contains('.')
            ? name.substring(name.lastIndexOf('.')).toLowerCase()
            : '';
        if (!mdExtensions.contains(ext) && !codeExtensions.contains(ext)) {
          continue;
        }
        final stat = entity.statSync();
        out.add(
          NoteFile(
            relativePath: entity.path
                .substring(root.path.length + 1)
                .replaceAll('\\', '/'),
            absolutePath: entity.path,
            modified: stat.modified,
            sizeBytes: stat.size,
          ),
        );
      }
    }
  }
}

/// 一篇本地笔记文件。
class NoteFile {
  const NoteFile({
    required this.relativePath,
    required this.absolutePath,
    required this.modified,
    required this.sizeBytes,
  });

  final String relativePath;
  final String absolutePath;
  final DateTime modified;
  final int sizeBytes;

  /// 文件名（不含扩展名），作为无 front-matter 时的标题。
  String get fileName {
    final base = relativePath.split('/').last;
    final dot = base.lastIndexOf('.');
    return dot > 0 ? base.substring(0, dot) : base;
  }

  String get extension {
    final base = relativePath.split('/').last;
    final dot = base.lastIndexOf('.');
    return dot > 0 ? base.substring(dot).toLowerCase() : '';
  }

  bool get isMarkdown => NoteScanner.mdExtensions.contains(extension);
}

/// 从 Markdown 文本头部解析 front-matter（--- 包裹的 key: value）。
class FrontMatter {
  const FrontMatter({this.title, this.tags = const [], required this.body});

  final String? title;
  final List<String> tags;
  final String body;

  static FrontMatter parse(String source) {
    if (!source.startsWith('---')) {
      return FrontMatter(title: null, tags: const [], body: source);
    }
    final end = source.indexOf('\n---', 3);
    if (end == -1) {
      return FrontMatter(title: null, tags: const [], body: source);
    }
    final header = source.substring(3, end).trim();
    String? title;
    final tags = <String>[];
    for (final line in header.split('\n')) {
      final idx = line.indexOf(':');
      if (idx == -1) continue;
      final key = line.substring(0, idx).trim().toLowerCase();
      final value = line.substring(idx + 1).trim();
      if (value.isEmpty) continue;
      if (key == 'title') {
        title = value.replaceAll(RegExp(r'^["\x27]|["\x27]$'), '');
      } else if (key == 'tags' || key == 'tag') {
        tags.addAll(
          value
              .split(RegExp(r'[,，]'))
              .map(
                (t) => t
                    .trim()
                    .replaceAll(RegExp('^["\\[\\]]|["\\[\\]]\$'), ''),
              )
              .where((t) => t.isNotEmpty),
        );
      }
    }
    return FrontMatter(
      title: title,
      tags: tags,
      body: source.substring(source.indexOf('\n', end + 1) + 1),
    );
  }
}
