import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader/src/git/sync_service.dart';
import 'package:reader/src/platforms/git_platform.dart';
import 'package:reader/src/platforms/repo_info.dart';

/// pull 的 fast-forward 路径（本地裸仓库，不依赖网络）：
/// 进度消息之外，还验证变更清单与工作区内容确实更新。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('pull-local');
  });

  tearDown(() {
    try {
      if (temp.existsSync()) temp.deleteSync(recursive: true);
    } on Object {
      // Windows 句柄未释放时忽略
    }
  });

  test('pull fast-forwards and reports changes', () async {
    final work = Directory('${temp.path}${Platform.pathSeparator}work')
      ..createSync();
    final remote = '${temp.path}${Platform.pathSeparator}remote.git';
    await _git(['init', '-b', 'main'], work);
    await _git(['config', 'user.email', 't@example.com'], work);
    await _git(['config', 'user.name', 'tester'], work);
    File('${work.path}${Platform.pathSeparator}a.md').writeAsStringSync('one');
    await _git(['add', '.'], work);
    await _git(['commit', '-m', 'first'], work);
    await _git(['init', '--bare', remote], temp);
    // 裸仓库默认 HEAD 指向 master，而内容推到 main：修正 HEAD，
    // 否则「检出远端 HEAD」的克隆会得到一个空工作区
    await _git(
      ['symbolic-ref', 'HEAD', 'refs/heads/main'],
      Directory(remote),
    );
    await _git(['remote', 'add', 'origin', remote], work);
    await _git(['push', '-u', 'origin', 'main'], work);

    final reposRoot = Directory('${temp.path}${Platform.pathSeparator}repos')
      ..createSync();
    final service = GitSyncService();
    final clonePath = await service.clone(
      repo: RepoInfo(
        platform: GitPlatform.github,
        owner: 'me',
        name: 'notes',
        cloneUrl: remote,
        defaultBranch: 'main',
      ),
      parentDir: reposRoot,
    );
    final cloned = Directory(clonePath);
    expect(File('${cloned.path}${Platform.pathSeparator}a.md').readAsStringSync(),
        'one');

    // 远端新增一个文件、修改一个文件
    File('${work.path}${Platform.pathSeparator}a.md').writeAsStringSync('two');
    File('${work.path}${Platform.pathSeparator}b.md').writeAsStringSync('new');
    await _git(['add', '.'], work);
    await _git(['commit', '-m', 'second'], work);
    await _git(['push', 'origin', 'main'], work);

    final progress = <CloneProgress>[];
    final outcome = await service.pull(
      repoDir: cloned,
      onProgress: progress.add,
    );

    expect(outcome.result, PullResult.fastForwarded);
    final paths = outcome.changes.map((c) => c.path).toSet();
    expect(paths, containsAll(['a.md', 'b.md']));
    expect(
      outcome.changes.firstWhere((c) => c.path == 'b.md').added,
      isTrue,
    );
    expect(
      File('${cloned.path}${Platform.pathSeparator}a.md').readAsStringSync(),
      'two',
      reason: 'fast-forward 后工作区应更新到远端内容',
    );
    expect(
      File('${cloned.path}${Platform.pathSeparator}b.md').existsSync(),
      isTrue,
    );

    // 再拉一次：已是最新，不应报错
    final again = await service.pull(repoDir: cloned);
    expect(again.result, PullResult.upToDate);
  });
}

Future<void> _git(List<String> args, Directory cwd) async {
  final result = await Process.run(
    'git',
    args,
    workingDirectory: cwd.path,
    stdoutEncoding: const SystemEncoding(),
    stderrEncoding: const SystemEncoding(),
  );
  if (result.exitCode != 0) {
    throw StateError('git ${args.join(' ')} failed: ${result.stderr}');
  }
}
