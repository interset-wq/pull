import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'note_scanner.dart';

/// 一篇带 front-matter 标签的笔记（跨仓库聚合用）。
class TaggedFile {
  const TaggedFile({
    required this.repoRoot,
    required this.repoName,
    required this.relativePath,
    required this.tags,
  });

  final String repoRoot;
  final String repoName;
  final String relativePath;
  final List<String> tags;
}

/// 标签聚合：扫描仓库（含本地文件夹镜像）里 md 的 front-matter `tags`，
/// 供标签页按标签筛选、跨仓库浏览。
///
/// 只读文件头（最多 [maxHeaderBytes] 字节）：标签都在 front-matter 里，
/// 不必把整篇正文读进内存，几万文件也能快速聚合。
class TagIndex {
  static const maxHeaderBytes = 8 * 1024;

  static Future<List<TaggedFile>> scan(
    List<Directory> roots, {
    bool useDefaults = true,
    List<String> customRules = const [],
    bool includeDirTags = false,
  }) {
    return Isolate.run(
      () => scanSync(
        roots: roots,
        useDefaults: useDefaults,
        customRules: customRules,
        includeDirTags: includeDirTags,
      ),
    );
  }

  /// 同步实现（isolate 入口，也便于单测）。
  ///
  /// [includeDirTags] 为 true 时，把文件的每级目录名并入 tags（隐式标签）：
  /// 没写 front-matter 的仓库也能用标签页导航。与显式 tags 合并去重。
  static List<TaggedFile> scanSync({
    required List<Directory> roots,
    bool useDefaults = true,
    List<String> customRules = const [],
    bool includeDirTags = false,
  }) {
    final out = <TaggedFile>[];
    for (final root in roots) {
      final files = NoteScanner(
        useDefaults: useDefaults,
        customRules: customRules,
      ).scan(root.path);
      final repoName = root.path.split(Platform.pathSeparator).last;
      for (final file in files) {
        if (!_isMarkdownLike(file.extension)) continue;
        final tags = _readTags(file.absolutePath);
        final dirs = includeDirTags ? _dirSegments(file.relativePath) : const <String>[];
        final merged = {...tags, ...dirs}.toList()..sort();
        if (merged.isEmpty) continue;
        out.add(
          TaggedFile(
            repoRoot: root.path,
            repoName: repoName,
            relativePath: file.relativePath,
            tags: merged,
          ),
        );
      }
    }
    return out;
  }

  /// 相对路径的目录段（不含文件名），`/` 与 `\` 都按分隔符处理。
  static List<String> _dirSegments(String relativePath) {
    final parts = relativePath
        .replaceAll('\\', '/')
        .split('/')
      ..removeLast();
    return [for (final p in parts) if (p.isNotEmpty) p];
  }

  static bool _isMarkdownLike(String ext) =>
      ext == '.md' || ext == '.markdown' || ext == '.mdx';

  /// 读文件头并解析 front-matter 标签；任何失败都视为无标签。
  static List<String> _readTags(String path) {
    RandomAccessFile? raf;
    try {
      raf = File(path).openSync();
      final length = raf.lengthSync();
      final take = length < maxHeaderBytes ? length : maxHeaderBytes;
      final bytes = raf.readSync(take);
      // 截断读取可能切在多字节字符中间：allowMalformed 保证不抛异常，
      // front-matter 的 `---`/键名都是 ASCII，能正常解析
      final text = utf8.decode(bytes, allowMalformed: true)
          .replaceFirst('\uFEFF', '');
      return FrontMatter.parse(text).tags;
    } on Object {
      return const [];
    } finally {
      try {
        raf?.closeSync();
      } on Object {
        // 忽略
      }
    }
  }
}
