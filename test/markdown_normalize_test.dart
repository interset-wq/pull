import 'package:flutter_test/flutter_test.dart';

import 'package:reader/src/ui/markdown_viewer.dart';

void main() {
  group('normalizeHtmlImages 真实案例', () {
    test('div 包裹的 img（README 首图）', () {
      const src = '''
# LLM Universe

<div align=center>
<img src="figures/C0-0-logo.png" width = "1000">
</div>
''';
      final out = MarkdownViewerPage.normalizeHtmlImages(src);
      expect(out.contains('<'), isFalse, reason: '不应残留任何 HTML 标签: $out');
      expect(out.contains("width"), isFalse, reason: '不应残留属性: $out');
      expect(out.contains('![](figures/C0-0-logo.png)'), isTrue);
    });

    test('自闭合 img 与单引号属性', () {
      const src = '<a href="https://x.com">\n'
          '  <img src=\'https://contrib.rocks/image?repo=a/b\' />\n'
          '</a>\n';
      final out = MarkdownViewerPage.normalizeHtmlImages(src);
      expect(out.contains('<'), isFalse, reason: '不应残留任何 HTML 标签: $out');
      expect(out.contains('/>'), isFalse, reason: '不应残留自闭合斜杠: $out');
      expect(out.contains('![](https://contrib.rocks/image?repo=a/b)'), isTrue);
    });

    test('徽章式链接图片展平', () {
      const src = '[![Stars](https://img.shields.io/stars?style=social)]'
          '(https://github.com/a/b/stargazers)\n'
          '![GitHub forks](https://img.shields.io/forks)\n';
      final out = MarkdownViewerPage.normalizeHtmlImages(src);
      expect(out.contains('[!['), isFalse);
      expect(
        out.contains('![Stars](https://img.shields.io/stars?style=social)'),
        isTrue,
      );
      expect(
        out.contains('![GitHub forks](https://img.shields.io/forks)'),
        isTrue,
      );
    });

    test('picture/source 包裹（star-history 常见写法）', () {
      const src = '''
<picture>
  <source media="(prefers-color-scheme: dark)" srcset="dark.svg">
  <img src="https://api.star-history.com/svg?repos=a/b&type=Date" alt="chart" />
</picture>
''';
      final out = MarkdownViewerPage.normalizeHtmlImages(src);
      expect(out.contains('<'), isFalse, reason: '不应残留任何 HTML 标签: $out');
      expect(out.contains('srcset'), isFalse);
      expect(
        out.contains('![](https://api.star-history.com/svg?repos=a/b&type=Date)'),
        isTrue,
      );
    });

    test('空 img 标签两种写法直接移除', () {
      const src = '<img>\n<img />\n';
      final out = MarkdownViewerPage.normalizeHtmlImages(src);
      expect(out.contains('img'), isFalse, reason: '空标签应被移除: $out');
      expect(out.contains('/>'), isFalse);
    });

    test('collectImageUrls 按文档顺序收集', () {
      const body = '![logo](figures/a.png)\n\n![](https://x.io/b.svg)\n';
      expect(
        MarkdownViewerPage.collectImageUrls(body),
        ['figures/a.png', 'https://x.io/b.svg'],
      );
    });
  });
}
