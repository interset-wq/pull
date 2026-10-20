import 'dart:io';

import 'package:git2dart/git2dart.dart';

import '../platforms/repo_info.dart';

/// 本地仓库同步服务：封装 git2dart 的克隆 / pull / commit / push。
/// 所有 git 操作必须经由本服务，业务代码不直接触碰 git2dart。
class GitSyncService {
  /// 克隆 [repo] 到 [parentDir] 下的同名目录。
  ///
  /// [token] 为对应平台的 PAT，作为 HTTPS Basic 凭据使用
  /// （用户名任意，密码用 token）。
  Future<String> clone({
    required RepoInfo repo,
    required Directory parentDir,
    required String token,
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
      callbacks: _credentials(token),
    );
    r.free();
    return target.path;
  }

  /// 拉取远端最新提交并 fast-forward 到本地分支。
  ///
  /// 只处理 fast-forward 场景：本地有独立提交或产生冲突时抛出
  /// [SyncException]，由上层 UI 决定如何提示——绝不做破坏性操作。
  Future<PullResult> pull({
    required Directory repoDir,
    required String token,
  }) async {
    final r = Repository.open(repoDir.path);
    try {
      final remote = Remote.lookup(repo: r, name: 'origin');
      remote.fetch(callbacks: _credentials(token));
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

  /// 提交指定文件的改动并 push 到远端同分支。
  ///
  /// 只提交 [paths] 列出的文件；无改动时返回 false。
  Future<bool> commitAndPush({
    required Directory repoDir,
    required List<String> paths,
    required String message,
    required String userName,
    required String userEmail,
    required String token,
  }) async {
    final r = Repository.open(repoDir.path);
    try {
      final index = r.index;
      index.addAll(paths);
      final treeOid = index.writeTree();
      index.write();
      if (_hasNoUncommittedChanges(r)) {
        return false;
      }

      final tree = Tree.lookup(repo: r, oid: treeOid);
      final signature = Signature.create(
        name: userName,
        email: userEmail,
        time: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        offset: DateTime.now().timeZoneOffset.inMinutes,
      );
      final parent = Commit.lookup(repo: r, oid: r.head.target);
      final branch = _currentBranch(r);

      Commit.create(
        repo: r,
        updateRef: 'refs/heads/$branch',
        author: signature,
        committer: signature,
        message: message,
        tree: tree,
        parents: [parent],
      );

      final remote = Remote.lookup(repo: r, name: 'origin');
      remote.push(
        refspecs: ['refs/heads/$branch'],
        callbacks: _credentials(token),
      );
      remote.free();
      return true;
    } finally {
      r.free();
    }
  }

  Callbacks _credentials(String token) => token.isEmpty
      ? const Callbacks()
      : Callbacks(credentials: UserPass(username: token, password: token));

  String _currentBranch(Repository r) {
    final head = r.head;
    final name = head.name;
    head.free();
    return name.replaceFirst('refs/heads/', '');
  }

  bool _hasNoUncommittedChanges(Repository r) {
    final status = r.status;
    return status.isEmpty;
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
