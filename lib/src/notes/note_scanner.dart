import 'dart:io';

export '../utils/natural_sort.dart';

/// 扫描本地仓库中的笔记（Markdown/Notebook）、代码、图片与其他文本文件。
class NoteScanner {
  /// 自定义隐藏规则（Roadmap「设置增强·Ignore 配置」）：按文件/目录名
  /// 精确匹配，跨仓库生效；由调用方从设置传入。
  NoteScanner({this.useDefaults = true, this.customRules = const []});

  /// 是否启用默认隐藏规则（点开头名 + [skipDirs]）。
  /// `.git` 恒被跳过——关掉默认规则也不进 git 内部目录。
  final bool useDefaults;
  final List<String> customRules;
  static const mdExtensions = {'.md', '.markdown', '.ipynb'};

  /// 支持语法高亮查看的代码/文本扩展名。
  static const codeExtensions = {
    '.dart', '.py', '.js', '.mjs', '.ts', '.tsx', '.jsx', '.java', '.kt',
    '.kts', '.go', '.rs', '.c', '.h', '.cpp', '.cc', '.hpp', '.cs', '.rb',
    '.php', '.swift', '.m', '.sh', '.bash', '.zsh', '.json', '.yaml', '.yml',
    '.toml', '.xml', '.html', '.css', '.scss', '.sql', '.r', '.lua', '.pl',
    '.txt', '.gradle', '.properties', '.cfg', '.ini', '.cmake',
    '.csv', '.tsv', '.log', '.env', '.mdx', '.diff', '.patch',
  };

  /// 可直接预览的图片扩展名。
  static const imageExtensions = {
    '.png', '.jpg', '.jpeg', '.gif', '.webp', '.bmp', '.svg',
  };

  /// 明确的二进制类型：不作为文本兜底展示。
  static const binaryExtensions = {
    '.exe', '.dll', '.so', '.dylib', '.bin', '.o', '.a', '.lib',
    '.zip', '.gz', '.tar', '.rar', '.7z', '.jar', '.apk', '.ipa',
    '.pdf', '.ttf', '.otf', '.woff', '.woff2', '.eot', '.ico',
    '.mp3', '.mp4', '.avi', '.mov', '.wav', '.flac', '.psd', '.class',
  };

  /// 未知类型的文本兜底大小上限：小文件按纯文本展示。
  static const unknownTextMaxBytes = 1 << 20; // 1 MB

  static const skipDirs = {'.git', 'node_modules', '.obsidian', 'temp'};

  /// 名称是否被隐藏：自定义规则（精确名匹配，文件与目录都生效）优先；
  /// 默认规则 = 点开头名 + skipDirs（.git 恒忽略）。
  bool isIgnored(String name) {
    if (name == '.git') return true;
    if (customRules.contains(name)) return true;
    if (!useDefaults) return false;
    return name.startsWith('.') || skipDirs.contains(name);
  }

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
      if (isIgnored(name)) continue;
      if (entity is Directory) {
        _walk(entity, root, out);
      } else if (entity is File) {
        final ext = name.contains('.')
            ? name.substring(name.lastIndexOf('.')).toLowerCase()
            : '';
        // 图片/已知文本直接收录；未注册类型兜底为小体积纯文本
        // （csv 等），保证任何目录都不会"解析不出文件"。
        final known = mdExtensions.contains(ext) ||
            codeExtensions.contains(ext) ||
            imageExtensions.contains(ext);
        if (!known) {
          if (binaryExtensions.contains(ext)) continue;
          final size = entity.lengthSync();
          if (size > unknownTextMaxBytes) continue;
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

  /// 纯文本（txt）：按纯文本阅读渲染，不走代码高亮。
  bool get isPlainText => extension == '.txt';

  bool get isImage => NoteScanner.imageExtensions.contains(extension);
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
