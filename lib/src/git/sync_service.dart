import 'dart:io';

import 'package:git2dart/git2dart.dart';

import '../platforms/repo_info.dart';

/// 本地仓库同步服务：封装 git2dart 的克隆 / pull。
/// 仅支持公开仓库，匿名访问，无需任何凭据。
class GitSyncService {
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
    final r = Repository.clone(
      url: repo.cloneUrl,
      localPath: target.path,
      checkoutBranch: repo.defaultBranch,
    );
    r.free();
    return target.path;
  }

  /// 拉取远端最新提交并 fast-forward 到本地分支。
  ///
  /// 只处理 fast-forward 场景：本地有独立提交或产生冲突时抛出
  /// [SyncException]，由上层 UI 决定如何提示——绝不做破坏性操作。
  Future<PullResult> pull({required Directory repoDir}) async {
    final r = Repository.open(repoDir.path);
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

  String _currentBranch(Repository r) {
    final head = r.head;
    final name = head.name;
    head.free();
    return name.replaceFirst('refs/heads/', '');
  }

  void _checkoutHead(Repository r) {
    final head = r.head;
    final oid = head.target;
    head.free();
    r.reset(oid: oid, resetType: GitReset.hard);
  }
}

enum PullResult { upToDate, fastForwarded }

class SyncException implements Exception {
  const SyncException(this.message);

  final String message;

  @override
  String toString() => message;
}
