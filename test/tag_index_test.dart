import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader/src/notes/tag_index.dart';

void main() {
  late Directory root;

  setUp(() {
    root = Directory(
      'temp/tag-index-${DateTime.now().microsecondsSinceEpoch}',
    )..createSync(recursive: true);
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  File write(String name, String content) {
    final file = File('${root.path}${Platform.pathSeparator}$name');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
    return file;
  }

  test('扫出 front-matter 标签，跳过没有标签的笔记', () {
    write('a.md', '---\ntitle: A\ntags: [flutter, 笔记]\n---\n正文');
    write('b.md', '---\ntags: flutter\n---\n正文');
    write('c.md', '没有 front-matter');
    write('d.txt', '---\ntags: x\n---');

    final files = TagIndex.scanSync(roots: [root]);
    expect(files.map((f) => f.relativePath).toSet(), {'a.md', 'b.md'});
    final byPath = {for (final f in files) f.relativePath: f};
    expect(byPath['a.md']!.tags, ['flutter', '笔记']);
    expect(byPath['b.md']!.tags, ['flutter']);
    expect(files.first.repoName, root.path.split(Platform.pathSeparator).last);
  });

  test('带 BOM 的文件也能解析 front-matter', () {
    final file = File('${root.path}${Platform.pathSeparator}bom.md');
    file.writeAsBytesSync([
      0xEF, 0xBB, 0xBF,
      ...utf8.encode('---\ntags: [x]\n---\n正文'),
    ]);
    final files = TagIndex.scanSync(roots: [root]);
    expect(files.single.tags, ['x']);
  });

  test('截断读取不会因多字节字符报错', () {
    // 文件头之后紧跟大量中文，确保 8KB 截断点落在汉字中间
    final body = '汉' * 8000;
    write('big.md', '---\ntags: [长文]\n---\n$body');
    final files = TagIndex.scanSync(roots: [root]);
    expect(files.single.tags, ['长文']);
  });

  test('多个仓库一起聚合，repoName 各自独立', () {
    final other = Directory('${root.path}${Platform.pathSeparator}other')
      ..createSync();
    write('a.md', '---\ntags: [t1]\n---');
    File('${other.path}${Platform.pathSeparator}b.md')
        .writeAsStringSync('---\ntags: [t2]\n---');

    final files = TagIndex.scanSync(roots: [root, other]);
    expect(files.map((f) => f.repoName).toSet(),
        {root.path.split(Platform.pathSeparator).last, 'other'});
    expect(files.map((f) => f.tags.single).toSet(), {'t1', 't2'});
  });
}
