import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader/src/notes/note_index.dart';
import 'package:reader/src/notes/note_scanner.dart';

void main() {
  group('NoteIndexCache 编解码', () {
    test('往返保留相对路径、修改时间与大小，绝对路径按仓库根重建', () {
      final files = [
        NoteFile(
          relativePath: 'notes/a.md',
          absolutePath: '/whatever/a.md',
          modified: DateTime.fromMillisecondsSinceEpoch(1700000000000),
          sizeBytes: 42,
        ),
      ];
      final decoded = NoteIndexCache.decode(
        NoteIndexCache.encode(files),
        '/repos/demo',
      );
      expect(decoded, isNotNull);
      expect(decoded!.length, 1);
      final file = decoded.single;
      expect(file.relativePath, 'notes/a.md');
      expect(file.modified.millisecondsSinceEpoch, 1700000000000);
      expect(file.sizeBytes, 42);
      expect(
        file.absolutePath,
        '/repos/demo${Platform.pathSeparator}notes'
        '${Platform.pathSeparator}a.md',
      );
    });

    test('损坏/结构不符的缓存返回 null（调用方回退为直接扫描）', () {
      expect(NoteIndexCache.decode('', '/r'), isNull);
      expect(NoteIndexCache.decode('{oops', '/r'), isNull);
      expect(NoteIndexCache.decode('{"files": "nope"}', '/r'), isNull);
    });

    test('条目字段缺失时跳过该条而不是整体失败', () {
      const json = '{"files": [{"p": "ok.md", "m": 1, "s": 2}, {"p": 3}]}';
      final decoded = NoteIndexCache.decode(json, '/r');
      expect(decoded!.map((f) => f.relativePath), ['ok.md']);
    });
  });

  test('后台 isolate 扫描能把 NoteFile 带回主 isolate', () async {
    final dir = Directory(
      'temp/note-index-scan-${DateTime.now().microsecondsSinceEpoch}',
    )..createSync(recursive: true);
    try {
      File('${dir.path}${Platform.pathSeparator}a.md')
          .writeAsStringSync('# a');
      Directory('${dir.path}${Platform.pathSeparator}sub').createSync();
      File('${dir.path}${Platform.pathSeparator}sub'
              '${Platform.pathSeparator}b.md')
          .writeAsStringSync('# b');

      final files = await scanNotesInBackground(dir.path);
      expect(
        files.map((f) => f.relativePath).toSet(),
        {'a.md', 'sub/b.md'},
      );
    } finally {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    }
  });
}
