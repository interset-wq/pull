// ignore_for_file: avoid_print
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:git2dart/git2dart.dart';

/// 复现两个无法克隆的仓库：
/// 1. interset-wq/x（fork 仓库）
/// 2. GitHub_Trending/bu/build-your-own-x（GH 镜像仓库）
void main() {
  for (final (url, dir) in [
    ('https://gitcode.com/interset-wq/x.git', 'temp/repro-x'),
    (
      'https://gitcode.com/GitHub_Trending/bu/build-your-own-x.git',
      'temp/repro-byox',
    ),
  ]) {
    test('clone $url', () async {
      final target = Directory(dir);
      if (target.existsSync()) {
        await target.delete(recursive: true);
      }
      final sw = Stopwatch()..start();
      try {
        final r = Repository.clone(url: url, localPath: target.path);
        r.free();
        print('OK in ${sw.elapsedMilliseconds}ms');
      } catch (e) {
        print('FAILED in ${sw.elapsedMilliseconds}ms: $e');
        rethrow;
      }
    }, timeout: const Timeout(Duration(minutes: 5)));
  }
}
