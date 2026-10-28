import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader/src/notes/link_check.dart';

void main() {
  group('extractLocalLinks', () {
    test('识别图片与链接，跳过外部 URL / 锚点 / mailto', () {
      const md = '![ok](img/a.png)\n'
          '[doc](../notes/b.md)\n'
          '[ext](https://example.com)\n'
          '[anchor](#top)\n'
          '[mail](mailto:a@b.c)\n';
      final links = LinkChecker.extractLocalLinks(
        md,
        sourceRelativePath: 'dir/readme.md',
      );
      expect(links.map((l) => l.target), ['dir/img/a.png', 'notes/b.md']);
      expect(links.first.isImage, isTrue);
      expect(links.last.isImage, isFalse);
    });

    test('代码块与行内代码里的链接不算引用', () {
      const md = '```md\n[in fence](nope.md)\n```\n'
          '`[inline](alsonope.md)`\n'
          '[real](ok.md)\n';
      final links = LinkChecker.extractLocalLinks(md);
      expect(links.map((l) => l.target), ['ok.md']);
    });

    test('HTML img/a 也检查', () {
      const md = '<img src="pic.png">\n<a href="page.md">p</a>\n';
      final links = LinkChecker.extractLocalLinks(md);
      expect(links.map((l) => l.target), ['pic.png', 'page.md']);
    });

    test('百分号编码的中文路径会还原', () {
      const md = '[中文](%E4%B8%AD%E6%96%87.md)';
      final links = LinkChecker.extractLocalLinks(
        md,
        sourceRelativePath: 'notes/readme.md',
      );
      expect(links.single.target, 'notes/中文.md');
    });
  });

  group('resolveTarget', () {
    test('相对引用基于所在目录，.. 不会越过仓库根', () {
      expect(
        LinkChecker.resolveTarget('../x.md', fromFile: 'a/b/c.md'),
        'a/x.md',
      );
      expect(
        LinkChecker.resolveTarget('../../../../x.md', fromFile: 'a/b/c.md'),
        'x.md',
      );
    });

    test('以 / 开头相对仓库根', () {
      expect(
        LinkChecker.resolveTarget('/assets/a.png', fromFile: 'a/b/c.md'),
        'assets/a.png',
      );
    });

    test('去掉 query 与锚点；外部协议返回 null', () {
      expect(
        LinkChecker.resolveTarget('x.md?raw=1#sec', fromFile: 'a/c.md'),
        'a/x.md',
      );
      expect(LinkChecker.resolveTarget('https://a.b/c', fromFile: 'c.md'), isNull);
      expect(LinkChecker.resolveTarget('#local', fromFile: 'c.md'), isNull);
      expect(LinkChecker.resolveTarget('//cdn/x', fromFile: 'c.md'), isNull);
    });
  });

  test('checkSync 只报真正缺失的本地目标', () {
    final root = Directory(
      'temp/link-check-${DateTime.now().microsecondsSinceEpoch}',
    )..createSync(recursive: true);
    addTearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });
    File('${root.path}${Platform.pathSeparator}b.md')
        .writeAsStringSync('# b');
    File('${root.path}${Platform.pathSeparator}a.md').writeAsStringSync(
      '[ok](b.md)\n![bad](img/missing.png)\n[ext](https://example.com)\n',
    );

    final broken = LinkChecker.checkSync(repoRoot: root.path);
    expect(broken.length, 1);
    expect(broken.single.sourceRelativePath, 'a.md');
    expect(broken.single.target, 'img/missing.png');
    expect(broken.single.isImage, isTrue);
  });
}
