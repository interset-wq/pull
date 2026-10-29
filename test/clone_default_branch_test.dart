import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader/src/git/sync_service.dart';
import 'package:reader/src/platforms/git_platform.dart';
import 'package:reader/src/platforms/repo_info.dart';

/// 克隆不再猜默认分支：调用方给错的 defaultBranch 也应一次成功，
/// 并检出远端 HEAD（这里是 master）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('clone-default-branch');
  });

  tearDown(() {
    try {
      if (temp.existsSync()) temp.deleteSync(recursive: true);
    } on Object {
      // Windows 句柄未释放时忽略
    }
  });

  test('clone checks out the remote default branch (master)', () async {
    final work = Directory('${temp.path}${Platform.pathSeparator}work')
      ..createSync();
    final remote = '${temp.path}${Platform.pathSeparator}remote.git';
    await _git(['init', '-b', 'master'], work);
    await _git(['config', 'user.email', 't@example.com'], work);
    await _git(['config', 'user.name', 'tester'], work);
    File('${work.path}${Platform.pathSeparator}note.md')
        .writeAsStringSync('# note');
    await _git(['add', '.'], work);
    await _git(['commit', '-m', 'first'], work);
    await _git(['init', '--bare', remote], temp);
    await _git(['remote', 'add', 'origin', remote], work);
    await _git(['push', '-u', 'origin', 'master'], work);

    final reposRoot = Directory('${temp.path}${Platform.pathSeparator}repos')
      ..createSync();
    final path = await GitSyncService().clone(
      repo: RepoInfo(
        platform: GitPlatform.github,
        owner: 'me',
        name: 'notes',
        cloneUrl: remote,
        // 故意给错的默认分支：旧实现会先按 main 克隆、失败后删目录重来
        defaultBranch: 'main',
      ),
      parentDir: reposRoot,
    );

    expect(
      File('$path${Platform.pathSeparator}note.md').existsSync(),
      isTrue,
      reason: '不猜分支时一次克隆就应检出远端 HEAD',
    );
    expect(GitSyncService.readHeadBranch(path), 'master');
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
