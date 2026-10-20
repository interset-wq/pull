// ignore_for_file: avoid_print
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:git2dart/git2dart.dart';

void main() {
  test('git2dart clone public repo', () async {
    final target = Directory('temp/git2dart-verify');
    if (target.existsSync()) {
      await target.delete(recursive: true);
    }
    final stopwatch = Stopwatch()..start();
    final repo = Repository.clone(
      url: 'https://gitcode.com/interset-wq/notes.git',
      localPath: target.path,
    );
    stopwatch.stop();
    final head = repo.head;
    final commit = Commit.lookup(repo: repo, oid: head.target);
    print('clone ok in ${stopwatch.elapsedMilliseconds}ms, HEAD=${commit.oid.sha}');
    commit.free();
    head.free();
    repo.free();
    expect(target.existsSync(), isTrue);
  }, timeout: const Timeout(Duration(minutes: 2)));
}
