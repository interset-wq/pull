import 'dart:io';
import 'dart:isolate';

import 'package:git2dart/git2dart.dart';

import '../platforms/repo_info.dart';

/// 本地仓库同步服务：封装 git2dart 的克隆 / pull / 本地删除。
/// 仅支持公开仓库，匿名访问，无需任何凭据。
/// 所有 git 操作均在后台 isolate 执行，避免大仓库卡死 UI。
class GitSyncService {
  /// 克隆 [repo] 到 [parentDir] 下的同名目录。
  ///
  /// libgit2 不支持浅克隆，大仓库耗时较长；已在后台 isolate 执行，
  /// UI 仅展示进度对话框。
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
    await Isolate.run(() {
      final r = Repository.clone(
        url: url,
        localPath: targetPath,
        checkoutBranch: branch,
      );
      r.free();
    });
    return targetPath;
  }

  /// 拉取远端最新提交并 fast-forward 到本地分支（后台 isolate 执行）。
  ///
  /// 只处理 fast-forward 场景：本地有独立提交或产生冲突时抛出
  /// [SyncException]，由上层 UI 决定如何提示——绝不做破坏性操作。
  Future<PullResult> pull({required Directory repoDir}) =>
      Isolate.run(() => _pullAt(repoDir.path));

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
