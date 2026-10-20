// ignore_for_file: avoid_print
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader/reader.dart';

// 针对真实仓库的功能验证：克隆 + pull（只读，不 push）。
void main() {
  const repo = RepoInfo(
    platform: GitPlatform.gitcode,
    owner: 'interset-wq',
    name: 'notes',
    cloneUrl: 'https://gitcode.com/interset-wq/notes.git',
    defaultBranch: 'main',
  );

  final sync = GitSyncService();
  late Directory parent;

  setUpAll(() {
    parent = Directory('temp/sync-verify');
    if (parent.existsSync()) parent.deleteSync(recursive: true);
    parent.createSync(recursive: true);
  });
  tearDownAll(() {
    if (parent.existsSync()) parent.deleteSync(recursive: true);
  });

  test('clone + pull notes repo', () async {
    final path = await sync.clone(
      repo: repo,
      parentDir: parent,
      token: '', // 公开仓库不需要凭据
    );
    print('cloned to $path');
    expect(Directory(path).existsSync(), isTrue);

    final result = await sync.pull(
      repoDir: Directory(path),
      token: '',
    );
    print('pull result: $result');
    expect(
      result,
      anyOf(equals(PullResult.upToDate), equals(PullResult.fastForwarded)),
    );
  }, timeout: const Timeout(Duration(minutes: 2)));
}
