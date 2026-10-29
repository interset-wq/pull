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
  /// 按目录记录在途的「优雅终止清理」：取消/超时后孤儿 isolate 仍会在
  /// 原生侧把克隆跑完，目录要等 isolate 退出才能删。
  static final Map<String, Future<void>> _gracefulCleanups = {};

  Future<String> clone({
    required RepoInfo repo,
    required Directory parentDir,
    void Function(CloneProgress progress)? onProgress,
    CloneCancelToken? cancelToken,
  }) async {
    final targetPath = '${parentDir.path}${Platform.pathSeparator}${repo.name}';
    // 上一次被取消/超时的克隆若还在原生代码里跑，等它退出并清理完目录，
    // 否则重试会在半成品/已完成目录上误报「本地目录已存在」
    await waitForCleanup(targetPath);
    _prepareTarget(targetPath);
    final url = repo.cloneUrl;
    final port = ReceivePort();
    final isolate = await Isolate.spawn(
      _cloneEntry,
      <Object?>[url, targetPath, port.sendPort],
    );
    var ok = false;
    // true = 克隆 isolate 可能正停在 libgit2 原生代码里（传输进行中），
    // 不能用 immediate kill 打断，否则进程崩溃（app 直接退出）
    var inNative = false;
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
            inNative = true;
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
      // 超时同样发生在原生克隆阻塞期间，走优雅终止
      inNative = true;
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
        if (inNative) {
          // 优雅终止：kill 请求推迟到 isolate 下次响应事件时生效
          // （原生克隆自然返回后），目录清理等 isolate 真正退出后再做，
          // 避免与仍在写盘的克隆抢文件句柄。登记在案供重试方等待。
          final cleanup = _shutdownGracefully(isolate, targetPath);
          _gracefulCleanups[targetPath] = cleanup;
          unawaited(cleanup);
        } else {
          isolate.kill(priority: Isolate.immediate);
          // 被杀掉的 isolate 可能还占着文件句柄（Windows 尤甚），重试几次
          await _removeDir(targetPath);
        }
      }
    }
  }

  /// 等待 [targetPath] 上一次被取消/超时克隆的孤儿 isolate 退出并清理完目录。
  ///
  /// 传输期间 isolate 停在 libgit2 原生代码里，`Isolate.immediate` 会打断
  /// 原生执行并崩溃进程（用户点取消后 app 直接退出就是这个原因）；
  /// 这里先挂退出监听、再发 `beforeNextEvent` 的 kill 请求兜底（若克隆
  /// 永久卡死也能最终终止），等 isolate 真正退出后清理半成品目录。
  static Future<void> _shutdownGracefully(Isolate isolate, String path) async {
    final exited = Completer<void>();
    final exitPort = RawReceivePort((_) => exited.complete());
    try {
      isolate.addOnExitListener(exitPort.sendPort);
      isolate.kill(priority: Isolate.beforeNextEvent);
      await exited.future;
    } finally {
      exitPort.close();
    }
    await _removeDir(path);
  }

  /// 等待某目录上一次被取消/超时克隆的孤儿 isolate 退出并完成目录清理。
  ///
  /// UI 在取消克隆后调用它再刷新仓库列表，避免展示半成品目录；
  /// 重试克隆也会在开始前隐式等待。
  static Future<void> waitForCleanup(String targetPath) async {
    final prev = _gracefulCleanups.remove(targetPath);
    if (prev != null) {
      try {
        await prev;
      } on Object {
        // 清理失败（句柄占用等）：下次 clone 的 _prepareTarget 还会兜底
      }
    }
  }

  /// isolate 入口：克隆结果经 port 回传（成功 true，失败为错误字符串）。
  /// 原生异常对象不能跨 isolate 发送，这里统一转字符串。
  static void _cloneEntry(List<Object?> args) {
    final url = args[0] as String;
    final path = args[1] as String;
    final send = args[2] as SendPort;
    try {
      _cloneAt(url, path, send);
      send.send(true);
    } on Object catch (e) {
      send.send('$e');
    }
  }

  /// 克隆到本地并检出远端 HEAD。
  ///
  /// 刻意不传 `checkoutBranch`：调用方对默认分支只能靠猜（以前猜 `main`，
  /// 猜错——比如默认分支是 `master` 的仓库——libgit2 会报
  /// `GIT_ERROR_REFERENCE`，随后整仓删掉重克隆，大仓库等于下载两遍）。
  /// 不指定分支时 libgit2 直接检出远端 HEAD，一次到位。
  static void _cloneAt(String url, String path, SendPort send) {
    final callbacks = Callbacks(
      transferProgress: (stats) => send.send(<Object?>[
        0,
        stats.receivedObjects,
        stats.totalObjects,
        stats.receivedBytes,
      ]),
    );
    final r = Repository.clone(
      url: url,
      localPath: path,
      callbacks: callbacks,
    );
    r.free();
  }

  /// 读取本地仓库当前分支名（克隆后写 meta 用；读不到返回 null）。
  static String? readHeadBranch(String repoPath) {
    try {
      final repo = Repository.open(repoPath);
      try {
        final head = repo.head;
        final name = head.name;
        head.free();
        return name.replaceFirst('refs/heads/', '');
      } finally {
        repo.free();
      }
    } on Object {
      return null;
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
  /// [onProgress] 在对象传输阶段回调（对象数/已传输字节）；拉取不可安全
  /// 取消（fetch 是阻塞原生调用，kill 可能留下半截 packfile），所以只做进度。
  Future<PullOutcome> pull({
    required Directory repoDir,
    void Function(CloneProgress progress)? onProgress,
  }) async {
    final path = repoDir.path;
    final port = ReceivePort();
    await Isolate.spawn(_pullEntry, <Object?>[path, port.sendPort]);
    try {
      // 消息协议：进度 [0, received, total, bytes]；
      // 成功 [1, 'ff'|'same', [[路径, 新增?], …]]；
      // 失败 [2, 文案, 是否分叉]
      await for (final msg in port.timeout(const Duration(minutes: 5))) {
        if (msg is! List || msg.isEmpty) continue;
        switch (msg[0]) {
          case 0:
            onProgress?.call(
              CloneProgress(
                receivedObjects: msg[1] as int,
                totalObjects: msg[2] as int,
                receivedBytes: msg[3] as int,
              ),
            );
          case 1:
            final rawChanges = (msg[2] as List?) ?? const [];
            return PullOutcome(
              msg[1] == 'ff' ? PullResult.fastForwarded : PullResult.upToDate,
              changes: [
                for (final c in rawChanges)
                  RepoChange(
                    path: (c as List)[0] as String,
                    added: c[1] as bool,
                  ),
              ],
            );
          case 2:
            throw SyncException(msg[1] as String, diverged: msg[2] == true);
        }
      }
      throw const SyncException('拉取失败：连接中断');
    } on TimeoutException {
      throw const SyncException('拉取超时（5 分钟）：网络过慢或仓库过大，请重试');
    } finally {
      port.close();
      // 超时/异常不 kill：打断正在写的 packfile 风险大于收益，
      // 让 isolate 自然结束（与改造前 Isolate.run().timeout() 的行为一致）
    }
  }

  static void _pullEntry(List<Object?> args) {
    final path = args[0] as String;
    final send = args[1] as SendPort;
    try {
      final outcome = _pullAt(path, send);
      send.send(<Object?>[
        1,
        outcome.result == PullResult.fastForwarded ? 'ff' : 'same',
        [
          for (final c in outcome.changes) [c.path, c.added],
        ],
      ]);
    } on SyncException catch (e) {
      send.send(<Object?>[2, e.message, e.diverged]);
    } on Object catch (e) {
      send.send(<Object?>[2, '$e', false]);
    }
  }

  static PullOutcome _pullAt(String path, SendPort progress) {
    final r = Repository.open(path);
    try {
      final remote = Remote.lookup(repo: r, name: 'origin');
      remote.fetch(
        callbacks: Callbacks(
          transferProgress: (stats) => progress.send(<Object?>[
            0,
            stats.receivedObjects,
            stats.totalObjects,
            stats.receivedBytes,
          ]),
        ),
      );
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

/// 对象传输进度（clone / pull 共用）：packfile 下载/索引阶段的快照。
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
