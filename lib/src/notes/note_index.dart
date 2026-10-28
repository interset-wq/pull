import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'note_scanner.dart';

/// 仓库文件列表的磁盘缓存 + 后台扫描。
///
/// 目录扫描（`listSync` 递归）在几千文件的仓库上会明显卡住首帧，所以：
/// - 扫描放到后台 isolate（[scanNotesInBackground]）；
/// - 结果按仓库缓存到 `<reposRoot>/.meta/index/<仓库名>.json`，打开时先
///   用缓存渲染，再后台重扫校正（stale-while-revalidate）——既有秒开，
///   又不会因为外部改动而长期显示旧列表。
class NoteIndexCache {
  /// 缓存有效期不设 TTL：每次打开都会后台重扫校正，缓存只负责首帧。
  static String encode(List<NoteFile> files) => jsonEncode({
        'version': 1,
        'files': [
          for (final f in files)
            {'p': f.relativePath, 'm': f.modified.millisecondsSinceEpoch, 's': f.sizeBytes},
        ],
      });

  /// 解析缓存；损坏/结构不符返回 null（调用方回退为直接扫描）。
  static List<NoteFile>? decode(String text, String repoRoot) {
    if (text.trim().isEmpty) return null;
    try {
      final raw = jsonDecode(text);
      if (raw is! Map) return null;
      final files = raw['files'];
      if (files is! List) return null;
      final sep = Platform.pathSeparator;
      final out = <NoteFile>[];
      for (final item in files) {
        if (item is! Map) continue;
        final rel = item['p'];
        final modified = item['m'];
        final size = item['s'];
        if (rel is! String || rel.isEmpty || modified is! num || size is! num) {
          continue;
        }
        out.add(
          NoteFile(
            relativePath: rel,
            absolutePath:
                '$repoRoot$sep${rel.replaceAll('/', sep)}',
            modified: DateTime.fromMillisecondsSinceEpoch(modified.toInt()),
            sizeBytes: size.toInt(),
          ),
        );
      }
      return out;
    } on Object {
      return null;
    }
  }

  /// 读缓存，失败返回 null。
  static List<NoteFile>? read(String repoRoot) {
    try {
      final file = _file(repoRoot);
      if (!file.existsSync()) return null;
      return decode(file.readAsStringSync(), repoRoot);
    } on Object {
      return null;
    }
  }

  /// 写缓存；内容与已有缓存一致时跳过（避免每次打开都重写大 JSON）。
  static Future<void> write(String repoRoot, List<NoteFile> files) async {
    try {
      final text = encode(files);
      final file = _file(repoRoot);
      if (file.existsSync() && file.readAsStringSync() == text) return;
      file.parent.createSync(recursive: true);
      await file.writeAsString(text, flush: true);
    } on Object {
      // 缓存写失败只影响下次首帧，不影响功能
    }
  }

  /// 删除缓存（仓库被删除/重命名时调用）。
  static void remove(String repoRoot) {
    try {
      final file = _file(repoRoot);
      if (file.existsSync()) file.deleteSync();
    } on Object {
      // 忽略
    }
  }

  /// `<reposRoot>/.meta/index/<仓库名>.json`（与 RepoMeta 同级，不污染仓库内容）。
  static File _file(String repoRoot) {
    final name = repoRoot.split(Platform.pathSeparator).last;
    final parent = Directory(repoRoot).parent.path;
    return File(
      '$parent${Platform.pathSeparator}.meta'
      '${Platform.pathSeparator}index'
      '${Platform.pathSeparator}$name.json',
    );
  }
}

/// 在后台 isolate 扫描仓库文件；返回值可直接跨 isolate 传递（纯数据对象）。
Future<List<NoteFile>> scanNotesInBackground(
  String repoRoot, {
  bool useDefaults = true,
  List<String> customRules = const [],
}) {
  return Isolate.run(
    () => NoteScanner(useDefaults: useDefaults, customRules: customRules)
        .scan(repoRoot),
  );
}
