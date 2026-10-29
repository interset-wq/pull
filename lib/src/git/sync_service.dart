import 'dart:async';
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
  ///
  /// 超时/失败必须留下干净状态：早期实现用 `Isolate.run(...).timeout()`，
  /// Future 超时后 isolate 仍在写文件、半成品目录残留，用户重试只会得到
  /// 「本地目录已存在」。这里改为可 kill 的 isolate，结束后清理目标目录。
  ///
  /// [onProgress] 在对象传输阶段被回调（对象数/字节）；[cancelToken.cancel()]
  /// 后下一条进度消息到达时即终止克隆并清理目录（传输是阻塞原生调用，
  /// 取消只能借下一次进度回调生效）。
  Future<String> clone({
    required RepoInfo repo,
    required Directory parentDir,
    void Function(CloneProgress progress)? onProgress,
    CloneCancelToken? cancelToken,
  }) async {
    final targetPath = '${parentDir.path}${Platform.pathSeparator}${repo.name}';
    _prepareTarget(targetPath);
    final url = repo.cloneUrl;
    final branch = repo.defaultBranch;
    final port = ReceivePort();
    final isolate = await Isolate.spawn(
      _cloneEntry,
      <Object?>[url, branch, targetPath, port.sendPort],
    );
    var ok = false;
    try {
      // 进度消息为 [0, received, total, bytes]；最终消息 true / 错误字符串
      await for (final msg in port.timeout(const Duration(minutes: 5))) {
        if (msg is List && msg.isNotEmpty && msg[0] == 0) {
          onProgress?.call(
            CloneProgress(
              receivedObjects: msg[1] as int,
              totalObjects: msg[2] as int,
              receivedBytes: msg[3] as int,
            ),
          );
          if (cancelToken?.isCancelled ?? false) {
            throw const SyncException('已取消克隆');
          }
          continue;
        }
        if (msg is String) {
          throw SyncException(msg);
        }
        ok = true;
        break;
      }
      if (!ok) throw const SyncException('克隆失败：连接中断');
      return targetPath;
    } on TimeoutException {
      isolate.kill(priority: Isolate.immediate);
      throw const SyncException(
        '克隆超时（5 分钟）：网络过慢或仓库过大，请重试',
      );
    } on SyncException {
      rethrow;
    } on Object catch (e) {
      throw SyncException('克隆失败：$e');
    } finally {
      port.close();
      if (!ok) {
        isolate.kill(priority: Isolate.immediate);
        // 被杀掉的 isolate 可能还占着文件句柄（Windows 尤甚），重试几次
        await _removeDir(targetPath);
      }
    }
  }

  /// isolate 入口：克隆结果经 port 回传（成功 true，失败为错误字符串）。
  /// 原生异常对象不能跨 isolate 发送，这里统一转字符串。
  static void _cloneEntry(List<Object?> args) {
    final url = args[0] as String;
    final branch = args[1] as String;
    final path = args[2] as String;
    final send = args[3] as SendPort;
    try {
      _cloneAt(url, branch, path, send);
      send.send(true);
    } on Object catch (e) {
      send.send('$e');
    }
  }

  static void _cloneAt(String url, String branch, String path, SendPort send) {
    final callbacks = Callbacks(
      transferProgress: (stats) => send.send(<Object?>[
        0,
        stats.receivedObjects,
        stats.totalObjects,
        stats.receivedBytes,
      ]),
    );
    try {
      final r = Repository.clone(
        url: url,
        localPath: path,
        checkoutBranch: branch,
        callbacks: callbacks,
      );
      r.free();
    } on Object {
      // fork 仓库的 default_branch 可能与实际分支不符
      // （GIT_ERROR_REFERENCE: refs/remotes/origin/<branch> not found）。
      // 回退为不指定分支：libgit2 检出远端 HEAD（真实默认分支）。
      final dir = Directory(path);
      if (dir.existsSync()) {
        try {
          dir.deleteSync(recursive: true);
        } on Object {
          // 删不掉时第二遍克隆会因目录存在失败，错误沿 port 回传
        }
      }
      final r = Repository.clone(url: url, localPath: path);
      r.free();
    }
  }

  /// 目标目录预检：有效仓库 → 报「已存在」；上次异常留下的半成品 → 清掉。
  static void _prepareTarget(String path) {
    final dir = Directory(path);
    if (!dir.existsSync()) return;
    try {
      final r = Repository.open(path);
      r.free();
      throw SyncException('本地目录已存在: $path');
    } on SyncException {
      rethrow;
    } on Object {
      // 打不开说明不是完整仓库（多为上次克隆被打断的残留）
      try {
        dir.deleteSync(recursive: true);
      } on Object {
        // 下面统一报错
      }
      if (dir.existsSync()) {
        throw SyncException('无法清理上次未完成的克隆目录: $path');
      }
    }
  }

  static Future<void> _removeDir(String path) async {
    for (var i = 0; i < 4; i++) {
      final dir = Directory(path);
      if (!dir.existsSync()) return;
      try {
        dir.deleteSync(recursive: true);
      } on Object {
        // 句柄未释放：稍等再试
      }
      if (!dir.existsSync()) return;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
  }


  /// 远端状态：fetch 之后统计本地落后多少个提交，**不移动本地分支**。
  ///
  /// 供仓库页「检查更新」使用：先告诉用户有多少新内容，再决定是否 pull。
  Future<RemoteStatus> checkRemote({required Directory repoDir}) {
    final path = repoDir.path;
    return Isolate.run(() {
      try {
        return _checkAt(path);
      } catch (e) {
        // 原生错误对象不能跨 isolate 发送，统一转普通异常
        throw Exception('$e');
      }
    }).timeout(const Duration(minutes: 2));
  }

  static RemoteStatus _checkAt(String path) {
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
      final head = r.head;
      final localOid = head.target;
      head.free();
      if (remoteOid.sha == localOid.sha) {
        return const RemoteStatus(behind: 0, upToDate: true);
      }
      // 从远端头出发、排除本地头可达的提交 → 正是本地没有的新提交
      final walker = RevWalk(r)
        ..push(remoteOid)
        ..hide(localOid);
      final behind = walker.walk(limit: 101).length;
      // 反向走一遍：本地有而远端没有的提交数 > 0 说明历史已分叉
      // （通常是远端改写了提交记录），此时 pull 必然无法 fast-forward
      var diverged = false;
      if (behind > 0) {
        final ahead = RevWalk(r)
          ..push(localOid)
          ..hide(remoteOid);
        diverged = ahead.walk(limit: 1).isNotEmpty;
      }
      return RemoteStatus(
        behind: behind,
        upToDate: behind == 0,
        diverged: diverged,
      );
    } finally {
      r.free();
    }
  }

  /// 拉取远端最新提交并 fast-forward 到本地分支（后台 isolate 执行）。
  ///
  /// 只处理 fast-forward 场景：本地有独立提交或产生冲突时抛出
  /// [SyncException]，由上层 UI 决定如何提示——绝不做破坏性操作。
  /// 成功 fast-forward 时同时返回本次变更的文件清单（相对仓库根、
  /// `/` 分隔），供「更新后的阅读感知」打标。
  Future<PullOutcome> pull({required Directory repoDir}) {
    final path = repoDir.path;
    return Isolate.run(() {
      try {
        return _pullAt(path);
      } catch (e) {
        throw Exception('$e');
      }
    }).timeout(const Duration(minutes: 5));
  }

  static PullOutcome _pullAt(String path) {
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
        return const PullOutcome(PullResult.upToDate);
      }
      if (!results.contains(GitMergeAnalysis.fastForward)) {
        throw const SyncException(
          '本地与远端已分叉，无法 fast-forward；请在电脑上手动处理',
          diverged: true,
        );
      }

      final head = r.head;
      final localOid = head.target;
      head.free();
      final localRef = Reference.lookup(repo: r, name: 'refs/heads/$branch');
      Reference.setTarget(
        repo: r,
        name: localRef.name,
        target: remoteOid,
      );
      _checkoutHead(r);
      return PullOutcome(
        PullResult.fastForwarded,
        changes: _changedFiles(r, from: localOid, to: remoteOid),
      );
    } finally {
      r.free();
    }
  }

  /// 两个提交间的文件变更清单（新增/修改，不含删除——删除的文件列表里
  /// 本来就不会再出现）。isolate 内执行，返回纯数据可跨 isolate 传递。
  static List<RepoChange> _changedFiles(
    Repository r, {
    required Oid from,
    required Oid to,
  }) {
    final changes = <RepoChange>[];
    try {
      final oldCommit = Commit.lookup(repo: r, oid: from);
      final newCommit = Commit.lookup(repo: r, oid: to);
      final diff = Diff.treeToTree(
        repo: r,
        oldTree: oldCommit.tree,
        newTree: newCommit.tree,
      );
      for (final delta in diff.deltas) {
        final path = delta.newFile.path;
        if (path.isEmpty) continue;
        changes.add(
          RepoChange(
            path: path.replaceAll('\\', '/'),
            added: delta.status == GitDelta.added,
          ),
        );
      }
      diff.free();
    } on Object {
      // 变更清单只用于展示打标，算不出来时静默跳过，不影响 pull 本身
    }
    return changes;
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

/// 克隆传输进度：对象传输阶段（packfile 下载/索引）的快照。
class CloneProgress {
  const CloneProgress({
    required this.receivedObjects,
    required this.totalObjects,
    required this.receivedBytes,
  });

  final int receivedObjects;
  final int totalObjects;
  final int receivedBytes;

  /// 0~1；totalObjects 未知（0）时返回 null，UI 显示不确定进度。
  double? get fraction =>
      totalObjects > 0 ? (receivedObjects / totalObjects).clamp(0.0, 1.0) : null;
}

/// 克隆取消令牌：UI 置位后，下一条进度消息到达时终止克隆并清理目录。
class CloneCancelToken {
  bool _cancelled = false;

  void cancel() => _cancelled = true;

  bool get isCancelled => _cancelled;
}

/// pull 的完整结果：结果类型 + fast-forward 时本次变更的文件清单。
class PullOutcome {
  const PullOutcome(this.result, {this.changes = const <RepoChange>[]});

  final PullResult result;

  /// 本次 pull 新增/修改的文件（相对仓库根，`/` 分隔）；仅展示用。
  final List<RepoChange> changes;
}

/// 一条文件变更：[added] 为 true 表示新文件，否则为修改。
class RepoChange {
  const RepoChange({required this.path, required this.added});

  final String path;
  final bool added;
}

/// 远端相对本地的状态（[behind] 上限 101，超过按 101 返回即可）。
class RemoteStatus {
  const RemoteStatus({
    required this.behind,
    required this.upToDate,
    this.diverged = false,
  });

  final int behind;
  final bool upToDate;

  /// 本地有远端没有的提交 → 历史已分叉（远端可能改写了提交记录），
  /// pull 无法 fast-forward，UI 应询问是否重新克隆。
  final bool diverged;
}

class SyncException implements Exception {
  const SyncException(this.message, {this.diverged = false});

  final String message;

  /// 本地与远端历史已分叉（远端可能改写了提交记录），只能重新克隆。
  final bool diverged;

  @override
  String toString() => message;
}
