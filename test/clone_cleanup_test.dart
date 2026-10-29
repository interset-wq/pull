// ignore_for_file: avoid_print
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader/src/git/sync_service.dart';
import 'package:reader/src/platforms/git_platform.dart';
import 'package:reader/src/platforms/repo_info.dart';

/// 回归：克隆失败/超时不能留下半成品目录，否则重试永远报
/// 「本地目录已存在」。旧实现用 `Isolate.run(...).timeout()`，超时后
/// isolate 仍在写文件、目录残留。
void main() {
  test('克隆失败后清理残留目录，半成品目录可被重新使用', () async {
    final parent = Directory('temp/clone-cleanup');
    if (parent.existsSync()) await parent.delete(recursive: true);
    parent.createSync(recursive: true);

    // 模拟上次克隆被打断：目录存在但不是有效仓库
    final target = Directory('${parent.path}${Platform.pathSeparator}demo');
    target.createSync(recursive: true);
    File('${target.path}${Platform.pathSeparator}junk.pack')
        .writeAsStringSync('partial');

    final service = GitSyncService();
    final repo = RepoInfo(
      platform: GitPlatform.github,
      owner: 'no-such-owner',
      name: 'demo',
      // 本地不存在的仓库：libgit2 立即失败，不依赖网络
      cloneUrl:
          'file:///${Directory.current.path.replaceAll('\\', '/')}/temp/no-such-repo',
    );

    await expectLater(
      service.clone(repo: repo, parentDir: parent),
      throwsA(isA<SyncException>()),
    );
    expect(
      target.existsSync(),
      isFalse,
      reason: '失败后必须清理目标目录，否则重试会被「目录已存在」挡住',
    );

    // 再次尝试同样不应因目录残留而报「已存在」，而是同样的克隆失败
    await expectLater(
      service.clone(repo: repo, parentDir: parent),
      throwsA(
        isA<SyncException>().having(
          (e) => e.message,
          'message',
          isNot(contains('已存在')),
        ),
      ),
    );
    expect(target.existsSync(), isFalse);
  }, timeout: const Timeout(Duration(minutes: 2)));
}
