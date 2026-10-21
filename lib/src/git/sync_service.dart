import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:git2dart/git2dart.dart';
import 'package:http/http.dart' as http;

import '../platforms/repo_info.dart';

/// 本地仓库同步服务：封装克隆 / pull / 本地删除。
/// 仅支持公开仓库，匿名访问，无需任何凭据。
///
/// 克隆策略：优先下载平台归档包（无历史、单次 HTTP，大仓库快得多），
/// 归档仓库以 `.reader-repo.json` 标记；失败时回退 git2dart 全量克隆。
/// 所有 git 操作均在后台 isolate 执行，避免大仓库卡死 UI。
class GitSyncService {
  /// 归档仓库标记文件：记录来源与分支，供 pull 重下归档使用。
  static const _markerName = '.reader-repo.json';

  /// 克隆 [repo] 到 [parentDir] 下的同名目录。
  Future<String> clone({
    required RepoInfo repo,
    required Directory parentDir,
  }) async {
    final target = Directory(
      '${parentDir.path}${Platform.pathSeparator}${repo.name}',
    );
    if (target.existsSync()) {
      throw SyncException('本地目录已存在: ${target.path}');
    }
    final url = repo.cloneUrl;
    final branch = repo.defaultBranch;
    final targetPath = target.path;
    try {
      await _downloadArchive(url, branch, targetPath, withMarker: true);
      return targetPath;
    } on Exception catch (e) {
      // 归档不可用时回退到 git2dart 全量克隆
      try {
        await _gitClone(url, branch, targetPath);
        return targetPath;
      } on Object catch (gitError) {
        throw SyncException('克隆失败: $e / $gitError');
      }
    }
  }

  /// 拉取远端最新内容。
  ///
  /// 归档仓库：重新下载归档并替换内容；git 仓库：fast-forward pull。
  Future<PullResult> pull({required Directory repoDir}) async {
    final marker = File(
      '${repoDir.path}${Platform.pathSeparator}$_markerName',
    );
    if (!marker.existsSync()) {
      return Isolate.run(() => _pullAt(repoDir.path));
    }
    final meta = jsonDecode(marker.readAsStringSync()) as Map<String, dynamic>;
    final url = meta['url'] as String;
    final branch = meta['branch'] as String;
    await _downloadArchive(
      url,
      branch,
      repoDir.path,
      withMarker: true,
      clearExisting: true,
    );
    return PullResult.fastForwarded;
  }

  /// 下载平台归档并解压到 [targetPath]。
  ///
  /// [clearExisting] 为 true 时先清空目录（pull 重下场景），保留标记文件。
  Future<void> _downloadArchive(
    String url,
    String branch,
    String targetPath, {
    required bool withMarker,
    bool clearExisting = false,
  }) async {
    final archiveUrl = _archiveUrl(url, branch);
    final res = await http
        .get(
          Uri.parse(archiveUrl),
          headers: const {'User-Agent': 'Mozilla/5.0'},
        )
        .timeout(const Duration(minutes: 10));
    if (res.statusCode != 200 || res.bodyBytes.isEmpty) {
      throw SyncException('归档下载失败 (${res.statusCode}): $archiveUrl');
    }
    final marker = File('$targetPath${Platform.pathSeparator}$_markerName');
    if (clearExisting && targetPath.isNotEmpty) {
      final dir = Directory(targetPath);
      await for (final e in dir.list()) {
        if (e.path == marker.path) continue;
        await e.delete(recursive: true);
      }
    } else {
      Directory(targetPath).createSync(recursive: true);
    }
    await Isolate.run(() => _extractZip(res.bodyBytes, targetPath));
    if (withMarker) {
      marker.writeAsStringSync(
        const JsonEncoder.withIndent(' ').convert({
          'url': url,
          'branch': branch,
          'syncedAt': DateTime.now().toIso8601String(),
        }),
      );
    }
  }

  /// 由 cloneUrl 推导平台归档地址。
  static String _archiveUrl(String cloneUrl, String branch) {
    final base = cloneUrl.endsWith('.git')
        ? cloneUrl.substring(0, cloneUrl.length - 4)
        : cloneUrl;
    if (base.contains('github.com')) {
      final parts = base.split('/');
      final owner = parts[parts.length - 2];
      final name = parts.last;
      return 'https://codeload.github.com/$owner/$name/zip/refs/heads/$branch';
    }
    if (base.contains('gitee.com')) {
      return '$base/repository/archive/$branch.zip';
    }
    // gitcode 及其余 Gitee v5 风格平台
    return '$base/archive/$branch.zip';
  }

  /// 解压 zip：自动剥离平台打包的单一根目录（如 repo-main/）。
  static void _extractZip(Uint8List bytes, String targetPath) {
    final archive = ZipDecoder().decodeBytes(bytes);
    String? root;
    for (final f in archive.files) {
      if (!f.isFile) continue;
      final seg = f.name.split('/').first;
      if (root == null) {
        root = '$seg/';
      } else if (!f.name.startsWith(root)) {
        root = '';
      }
    }
    for (final f in archive.files) {
      if (!f.isFile) continue;
      final rel = root != null && root.isNotEmpty && f.name.startsWith(root)
          ? f.name.substring(root.length)
          : f.name;
      if (rel.isEmpty) continue;
      final file = File(
        '$targetPath${Platform.pathSeparator}'
        '${rel.replaceAll('/', Platform.pathSeparator)}',
      );
      file.createSync(recursive: true);
      file.writeAsBytesSync(f.content as List<int>);
    }
  }

  /// git2dart 全量克隆（归档不可用时的回退路径）。
  Future<void> _gitClone(String url, String branch, String targetPath) async {
    await Isolate.run(() {
      final r = Repository.clone(
        url: url,
        localPath: targetPath,
        checkoutBranch: branch,
      );
      r.free();
    });
  }

  /// git2dart fast-forward pull：本地有独立提交或冲突时抛出
  /// [SyncException]，由上层 UI 决定如何提示——绝不做破坏性操作。
  static PullResult _pullAt(String path) {
    final r = Repository.open(path);
    try {
      final remote = Remote.lookup(repo: r, name: 'origin');
      remote.fetch();
      remote.free();

      final branch = _currentBranch(r);
      final remoteOid = Reference.nameToId(
        repo: r,
        refName: 'refs/remotes/origin/$branch',
      );

      final analysis = Merge.analysis(repo: r, theirHead: remoteOid);
      final results = analysis.result;
      if (results.contains(GitMergeAnalysis.upToDate)) {
        return PullResult.upToDate;
      }
      if (!results.contains(GitMergeAnalysis.fastForward)) {
        throw SyncException(
          '本地与远端已分叉，无法 fast-forward；请在电脑上手动处理',
        );
      }

      final localRef = Reference.lookup(repo: r, name: 'refs/heads/$branch');
      Reference.setTarget(
        repo: r,
        name: localRef.name,
        target: remoteOid,
      );
      _checkoutHead(r);
      return PullResult.fastForwarded;
    } finally {
      r.free();
    }
  }

  static String _currentBranch(Repository r) {
    final head = r.head;
    final name = head.name;
    head.free();
    return name.replaceFirst('refs/heads/', '');
  }

  static void _checkoutHead(Repository r) {
    final head = r.head;
    final oid = head.target;
    head.free();
    r.reset(oid: oid, resetType: GitReset.hard);
  }

  /// 删除本地仓库目录（不影响远端）。
  ///
  /// Windows 下 .git 的对象文件是只读的，系统递归删除会失败，
  /// 用 `rmdir /s /q` 清只读删除；其余平台只读文件可直接 unlink。
  Future<void> deleteRepo(String path) async {
    final dir = Directory(path);
    if (!dir.existsSync()) return;
    if (Platform.isWindows) {
      final res = await Process.run(
        'cmd.exe',
        ['/c', 'rmdir', '/s', '/q', path],
      );
      if (dir.existsSync()) {
        throw SyncException('删除失败: ${res.stderr}');
      }
    } else {
      await dir.delete(recursive: true);
    }
  }
}

enum PullResult { upToDate, fastForwarded }

class SyncException implements Exception {
  const SyncException(this.message);

  final String message;

  @override
  String toString() => message;
}
