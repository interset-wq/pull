import 'dart:io';
import 'dart:isolate';

import '../notes/ipynb.dart';
import '../notes/note_scanner.dart';
import '../utils/text_encoding.dart';
import 'text_search.dart';

/// 仓库正文检索：在后台 isolate 里读候选文件、匹配、抽取摘要，
/// 主 isolate 只负责展示（大仓库不卡 UI）。
///
/// 刻意不建倒排索引：中文 2-gram 倒排的条目数与正文字符数同量级，
/// 在手机上序列化成 JSON 往往比正文本身还大；而笔记仓库的正文通常只有
/// 几 MB，读盘（页缓存）＋线性 `indexOf` 已经足够快，且没有索引过期问题。
class RepoSearchService {
  /// 单个文件参与检索的大小上限：超大文件（日志/导出）跳过，避免拖慢。
  static const maxFileBytes = 2 * 1024 * 1024;

  /// 最多返回多少个命中文件（按命中次数排序）。
  static const maxHitFiles = 60;

  /// 检索 [repoRoot] 下 md / ipynb 的正文。
  ///
  /// [files] 传入已扫描好的列表可复用仓库页缓存；为 null 时在 isolate
  /// 内自行扫描（遵守同一套 ignore 规则）。
  /// [titleOnly] 为 true 时只按文件名/路径匹配，不读文件内容（快得多，
  /// 命中不含摘要，仅作为文件清单过滤）。
  static Future<List<FileSearchResult>> search({
    required String repoRoot,
    required String query,
    List<NoteFile>? files,
    bool useDefaults = true,
    List<String> customRules = const [],
    bool titleOnly = false,
  }) {
    final q = query.trim();
    if (q.isEmpty) return Future.value(const []);
    return Isolate.run(
      () => searchSync(
        repoRoot: repoRoot,
        query: q,
        files: files,
        useDefaults: useDefaults,
        customRules: customRules,
        titleOnly: titleOnly,
      ),
    );
  }

  /// 同步实现（isolate 入口也直接调它，便于单测）。
  static List<FileSearchResult> searchSync({
    required String repoRoot,
    required String query,
    List<NoteFile>? files,
    bool useDefaults = true,
    List<String> customRules = const [],
    bool titleOnly = false,
  }) {
    final q = query.trim();
    if (q.isEmpty) return const [];
    final candidates = files ??
        NoteScanner(useDefaults: useDefaults, customRules: customRules)
            .scan(repoRoot);
    final results = <FileSearchResult>[];
    final terms = splitSearchTerms(q);
    if (titleOnly) {
      for (final note in candidates) {
        final path = note.relativePath.toLowerCase();
        if (terms.every(path.contains)) {
          results.add(
            FileSearchResult(
              relativePath: note.relativePath,
              matches: 1,
              snippets: const [],
            ),
          );
        }
      }
      results.sort((a, b) => a.relativePath.compareTo(b.relativePath));
      if (results.length > maxHitFiles) {
        results.removeRange(maxHitFiles, results.length);
      }
      return results;
    }
    for (final note in candidates) {
      if (!_isSearchable(note)) continue;
      final String content;
      try {
        final stat = File(note.absolutePath).statSync();
        if (stat.size > maxFileBytes) continue;
        final raw = decodeTextBytes(
          File(note.absolutePath).readAsBytesSync(),
        );
        content = note.extension == '.ipynb'
            // 检索只要文字：跳过内嵌图片的解码与内存占用
            ? IpynbConverter.toMarkdown(raw, includeImages: false)
            : raw;
      } on Object {
        // 读不了的文件跳过（权限/编码/正在写入）
        continue;
      }
      final hit = searchInText(
        relativePath: note.relativePath,
        content: content,
        query: q,
      );
      if (hit != null) results.add(hit);
    }
    results.sort((a, b) {
      // 标题/路径里命中全部关键词的排前面：搜「flutter 状态」时，
      // flutter-state.md 比正文里凑巧出现两词的长文更可能是目标。
      final rankA = _titleRank(a.relativePath, terms);
      final rankB = _titleRank(b.relativePath, terms);
      if (rankA != rankB) return rankA.compareTo(rankB);
      final byCount = b.matches.compareTo(a.matches);
      return byCount != 0
          ? byCount
          : a.relativePath.compareTo(b.relativePath);
    });
    if (results.length > maxHitFiles) {
      results.removeRange(maxHitFiles, results.length);
    }
    return results;
  }

  static bool _isSearchable(NoteFile note) =>
      note.extension == '.md' ||
      note.extension == '.markdown' ||
      note.extension == '.mdx' ||
      note.extension == '.ipynb';

  /// 0 = 路径里包含全部关键词（排序优先级最高）。
  static int _titleRank(String relativePath, List<String> terms) {
    final path = relativePath.toLowerCase();
    return terms.every(path.contains) ? 0 : 1;
  }
}
