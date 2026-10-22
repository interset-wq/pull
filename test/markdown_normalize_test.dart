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
          "  <img src='https://example.com/avatar.png' />\n"
          '</a>\n';
      final out = MarkdownViewerPage.normalizeHtmlImages(src);
      expect(out.contains('<'), isFalse, reason: '不应残留任何 HTML 标签: $out');
      expect(out.contains('/>'), isFalse, reason: '不应残留自闭合斜杠: $out');
      expect(out.contains('![](https://example.com/avatar.png)'), isTrue);
    });

    test('徽章式链接图片直接忽略（不渲染 SVG 徽章）', () {
      const src = '[![Stars](https://img.shields.io/stars?style=social)]'
          '(https://github.com/a/b/stargazers)\n'
          '![GitHub forks](https://img.shields.io/forks)\n'
          '<a href="https://x.com">\n'
          "  <img src='https://contrib.rocks/image?repo=a/b' />\n"
          '</a>\n';
      final out = MarkdownViewerPage.normalizeHtmlImages(src);
      expect(out.contains('shields.io'), isFalse);
      expect(out.contains('contrib.rocks'), isFalse);
      expect(out.contains('[!['), isFalse);
      expect(out.contains('![]('), isFalse);
    });

    test('picture/source 包裹（star-history 常见写法）直接忽略', () {
      const src = '''
<picture>
  <source media="(prefers-color-scheme: dark)" srcset="dark.svg">
  <img src="https://api.star-history.com/svg?repos=a/b&type=Date" alt="chart" />
</picture>
''';
      final out = MarkdownViewerPage.normalizeHtmlImages(src);
      expect(out.contains('<'), isFalse, reason: '不应残留任何 HTML 标签: $out');
      expect(out.contains('srcset'), isFalse);
      expect(out.contains('star-history.com'), isFalse);
    });

    test('本地 .svg 资源同样忽略，位图正常保留', () {
      const src = '![dark](assets/dark.svg)\n![photo](figures/pic.png)\n';
      final out = MarkdownViewerPage.normalizeHtmlImages(src);
      expect(out.contains('dark.svg'), isFalse);
      expect(out.contains('![photo](figures/pic.png)'), isTrue);
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

    test('行内样式标签 strong/em/code 保留', () {
      const src = '<strong>粗</strong> 与 <em>斜</em> 与 <code>x=1</code>\n';
      final out = MarkdownViewerPage.normalizeHtmlImages(src);
      expect(out.contains('<strong>粗</strong>'), isTrue, reason: out);
      expect(out.contains('<em>斜</em>'), isTrue);
      expect(out.contains('<code>x=1</code>'), isTrue);
    });

    test('div/span 等块级包装标签被剥离', () {
      const src = '<div align="center">\n\n正文内容\n\n</div>\n';
      final out = MarkdownViewerPage.normalizeHtmlImages(src);
      expect(out.contains('div'), isFalse, reason: out);
      expect(out.contains('正文内容'), isTrue);
    });
  });
}
