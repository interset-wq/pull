// ignore_for_file: avoid_print
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader/src/git/sync_service.dart';
import 'package:reader/src/platforms/git_platform.dart';
import 'package:reader/src/platforms/repo_info.dart';

/// 回归：fork 仓库 default_branch 与实际分支不符时，
/// clone 报 GIT_ERROR_REFERENCE；应自动回退为检出远端 HEAD。
void main() {
  test('clone with wrong defaultBranch falls back to remote HEAD',
      () async {
    final parent = Directory('temp/clone-fallback');
    if (parent.existsSync()) {
      await parent.delete(recursive: true);
    }
    parent.createSync(recursive: true);
    final service = GitSyncService();
    final path = await service.clone(
      repo: const RepoInfo(
        platform: GitPlatform.gitcode,
        owner: 'interset-wq',
        name: 'notes',
        cloneUrl: 'https://gitcode.com/interset-wq/notes.git',
        // 故意给一个不存在的分支，模拟 fork 的 default_branch 异常
        defaultBranch: 'no-such-branch',
      ),
      parentDir: parent,
    );
    expect(Directory(path).existsSync(), isTrue);
    expect(Directory('$path/.git').existsSync(), isTrue);
    final head = File('$path${Platform.pathSeparator}.git'
            '${Platform.pathSeparator}HEAD')
        .readAsStringSync();
    print('HEAD ref: ${head.trim()}');
  }, timeout: const Timeout(Duration(minutes: 3)));
}
