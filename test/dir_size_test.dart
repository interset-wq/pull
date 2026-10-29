import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader/src/utils/dir_size.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('formatBytes', () {
    test('formats each unit', () {
      expect(formatBytes(0), '0 B');
      expect(formatBytes(1023), '1023 B');
      expect(formatBytes(1024), '1.0 KB');
      expect(formatBytes(1536), '1.5 KB');
      expect(formatBytes(1024 * 1024), '1.0 MB');
      expect(formatBytes(100 * 1024 * 1024), '100 MB');
      expect(formatBytes(1024 * 1024 * 1024), '1.0 GB');
    });
  });

  group('dirSizeInBackground', () {
    late Directory root;

    setUp(() {
      root = Directory.systemTemp.createTempSync('dir-size');
    });

    tearDown(() {
      try {
        if (root.existsSync()) root.deleteSync(recursive: true);
      } on Object {
        // 忽略
      }
    });

    test('sums nested and hidden files', () async {
      File('${root.path}${Platform.pathSeparator}a.txt')
          .writeAsBytesSync(List.filled(100, 1));
      final sub = Directory('${root.path}${Platform.pathSeparator}sub')
        ..createSync();
      File('${sub.path}${Platform.pathSeparator}b.bin')
          .writeAsBytesSync(List.filled(250, 1));
      File('${root.path}${Platform.pathSeparator}.hidden')
          .writeAsBytesSync(List.filled(5, 1));

      expect(await dirSizeInBackground(root.path), 355,
          reason: '隐藏文件也应计入（与存储页口径一致）');
    });

    test('missing path and empty path are zero', () async {
      expect(await dirSizeInBackground(''), 0);
      expect(
        await dirSizeInBackground(
          '${root.path}${Platform.pathSeparator}missing',
        ),
        0,
      );
    });
  });
}
