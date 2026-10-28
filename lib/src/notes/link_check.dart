import 'dart:io';
import 'dart:isolate';

import '../notes/note_scanner.dart';
import '../utils/text_encoding.dart';

/// 一处本地链接/图片引用（已解析为仓库内相对路径）。
class LocalLink {
  const LocalLink({required this.target, required this.isImage});

  /// 仓库内相对路径（`/` 分隔，已归一化 `./` `../`、去锚点、解码百分号）。
  final String target;

  /// true = 图片引用；false = 普通链接。
  final bool isImage;
}

/// 一条断链记录。
class BrokenLink {
  const BrokenLink({
    required this.sourceRelativePath,
    required this.target,
    required this.isImage,
  });

  /// 引用所在文件（仓库内相对路径）。
  final String sourceRelativePath;

  /// 解析后的目标路径（不存在）。
  final String target;

  final bool isImage;
}

/// 断链检查：只解析仓库内相对链接/图片，外部 URL、锚点、mailto 一律跳过。
///
/// 只读操作，不会修改任何文件；结果供仓库页「检查断链」展示。
class LinkChecker {
  /// 单文件大小上限：超大 md 跳过（日志/导出文件）。
  static const maxFileBytes = 2 * 1024 * 1024;

  static Future<List<BrokenLink>> check({
    required String repoRoot,
    List<NoteFile>? files,
    bool useDefaults = true,
    List<String> customRules = const [],
  }) {
    return Isolate.run(
      () => checkSync(
        repoRoot: repoRoot,
        files: files,
        useDefaults: useDefaults,
        customRules: customRules,
      ),
    );
  }

  static List<BrokenLink> checkSync({
    required String repoRoot,
    List<NoteFile>? files,
    bool useDefaults = true,
    List<String> customRules = const [],
  }) {
    final notes = files ??
        NoteScanner(useDefaults: useDefaults, customRules: customRules)
            .scan(repoRoot);
    final broken = <BrokenLink>[];
    for (final note in notes) {
      if (!_isMarkdown(note.extension)) continue;
      final String text;
      try {
        if (File(note.absolutePath).lengthSync() > maxFileBytes) continue;
        text = decodeTextBytes(File(note.absolutePath).readAsBytesSync());
      } on Object {
        continue;
      }
      for (final link in extractLocalLinks(
        text,
        sourceRelativePath: note.relativePath,
      )) {
        final path = '$repoRoot${Platform.pathSeparator}'
            '${link.target.replaceAll('/', Platform.pathSeparator)}';
        final exists = File(path).existsSync() || Directory(path).existsSync();
        if (exists) continue;
        broken.add(
          BrokenLink(
            sourceRelativePath: note.relativePath,
            target: link.target,
            isImage: link.isImage,
          ),
        );
      }
    }
    broken.sort((a, b) {
      final byFile = a.sourceRelativePath.compareTo(b.sourceRelativePath);
      return byFile != 0 ? byFile : a.target.compareTo(b.target);
    });
    return broken;
  }

  static bool _isMarkdown(String ext) =>
      ext == '.md' || ext == '.markdown' || ext == '.mdx';

  static final _image = RegExp(
    r'!\[[^\]]*\]\(\s*([^)\s]+?)(?:\s+"[^"]*")?\s*\)',
  );
  static final _link = RegExp(
    r'(?<!!)\[[^\]]*\]\(\s*([^)\s]+?)(?:\s+"[^"]*")?\s*\)',
  );
  static final _htmlImg = RegExp(
    r'''<img[^>]*\ssrc\s*=\s*["']([^"']+)["']''',
    caseSensitive: false,
  );
  static final _htmlA = RegExp(
    r'''<a[^>]*\shref\s*=\s*["']([^"']+)["']''',
    caseSensitive: false,
  );
  static final _fence = RegExp(r'```[\s\S]*?```|~~~[\s\S]*?~~~');
  static final _inlineCode = RegExp(r'`[^`\n]*`');

  /// 提取 Markdown 文本里的本地链接（顺序：按出现位置）。
  ///
  /// [sourceRelativePath] 是这段 Markdown 自身在仓库内的相对路径——
  /// 相对链接要基于它所在目录解析。代码块/行内代码里的「链接」不算。
  static List<LocalLink> extractLocalLinks(
    String markdown, {
    String sourceRelativePath = '',
  }) {
    final text = markdown
        .replaceAll(_fence, '')
        .replaceAll(_inlineCode, '');
    final found = <({int at, LocalLink link})>[];
    void take(RegExp re, bool isImage) {
      for (final m in re.allMatches(text)) {
        final target = resolveTarget(
          m.group(1)!,
          fromFile: sourceRelativePath,
        );
        if (target == null) continue;
        found.add((
          at: m.start,
          link: LocalLink(target: target, isImage: isImage),
        ));
      }
    }

    take(_image, true);
    take(_htmlImg, true);
    take(_link, false);
    take(_htmlA, false);
    found.sort((a, b) => a.at.compareTo(b.at));
    return [for (final f in found) f.link];
  }

  /// 把引用地址解析成仓库内相对路径：
  /// - 外部 URL / 锚点 / mailto / 空 → null（不检查）
  /// - 以 `/` 开头 → 相对仓库根
  /// - 否则相对 [fromFile] 所在目录（`..` 逐级回退，不会越过仓库根）
  static String? resolveTarget(String rawHref, {String fromFile = ''}) {
    var href = rawHref.trim();
    if (href.isEmpty) return null;
    final lower = href.toLowerCase();
    if (lower.startsWith('http://') ||
        lower.startsWith('https://') ||
        lower.startsWith('//') ||
        lower.startsWith('mailto:') ||
        lower.startsWith('tel:') ||
        lower.startsWith('data:') ||
        href.startsWith('#')) {
      return null;
    }
    final hash = href.indexOf('#');
    if (hash >= 0) href = href.substring(0, hash);
    final query = href.indexOf('?');
    if (query >= 0) href = href.substring(0, query);
    if (href.isEmpty) return null;
    href = _decode(href);
    final fromRoot = href.startsWith('/');
    final out = <String>[];
    if (!fromRoot && fromFile.contains('/')) {
      out.addAll(
        fromFile
            .substring(0, fromFile.lastIndexOf('/'))
            .split('/')
            .where((s) => s.isNotEmpty),
      );
    }
    for (final seg in href.split('/')) {
      if (seg.isEmpty || seg == '.') continue;
      if (seg == '..') {
        if (out.isNotEmpty) out.removeLast();
        continue;
      }
      out.add(seg);
    }
    return out.join('/');
  }

  /// 与 markdown 渲染一致：CommonMark 会把中文文件名百分号编码，需要还原。
  static String _decode(String src) {
    if (!src.contains('%')) return src;
    try {
      return Uri.decodeFull(src);
    } on Object {
      return src;
    }
  }
}
