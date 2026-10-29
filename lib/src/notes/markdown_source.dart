/// Markdown 源码层面的纯处理：HTML 图片归一化、图片地址收集、阅读时长估算
/// 与标题锚点 slug。从阅读页抽出来单独成库——不依赖 Flutter，便于单测，
/// 也避免 `markdown_viewer.dart` 继续膨胀。
library;

/// 匹配 <img src="...">（属性顺序任意、单双引号均可、含尾部其余属性）。
final RegExp _htmlImgRegExp = RegExp(
  r'''<img[^>]*\ssrc=["']([^"']+)["'][^>]*>''',
  caseSensitive: false,
);

/// [![alt](img)](link) 徽章式链接图片展平为纯图片。
final RegExp _badgeLinkImgRegExp = RegExp(
  r'\[!\[([^\]]*)\]\(([^)\s]+)\)\]\(([^)]+)\)',
);

/// SVG 徽章类图片直接忽略：非常用位图格式、难以排版
/// （shields.io / contrib.rocks / star-history / .svg 文件）。
final RegExp _ignoredImageRegExp = RegExp(
  r'!\[[^\]]*\]\((?:[^)]*\.svg(?:\?[^)]*)?'
  r'|https?://img\.shields\.io/[^)]*'
  r'|https?://contrib\.rocks/[^)]*'
  r'|https?://api\.star-history\.com/[^)]*)\)',
  caseSensitive: false,
);

/// 代码保护段：围栏代码块（``` / ~~~，允许未闭合）与行内代码（单反引号）。
/// 匹配到的段落内不做任何 HTML 归一化，标签原样显示。
final RegExp _codeProtectedRegExp = RegExp(
  r'```[\s\S]*?(?:```|$)|~~~[\s\S]*?(?:~~~|$)|`[^`\n]*`',
);

/// <div><img src="x"/></div> 等 HTML 内嵌图片转 Markdown 图片语法，
/// 徽章链接展平为纯图片，同时归一化 <br> 与块级 div/p/a 包裹。
String normalizeHtmlImages(String md) {
  final out = StringBuffer();
  var cursor = 0;
  for (final m in _codeProtectedRegExp.allMatches(md)) {
    out
      ..write(_normalizeHtmlImagesPlain(md.substring(cursor, m.start)))
      ..write(m.group(0)!);
    cursor = m.end;
  }
  out.write(_normalizeHtmlImagesPlain(md.substring(cursor)));
  return out.toString();
}

/// 普通文本段的 HTML 归一化（调用前已剥离代码保护段）。
String _normalizeHtmlImagesPlain(String md) {
  final stripped = md
      .replaceAllMapped(
        _htmlImgRegExp,
        (m) => '\n\n![](${m.group(1)!})\n\n',
      )
      .replaceAllMapped(
        _badgeLinkImgRegExp,
        (m) => '![${m.group(1)!}](${m.group(2)!})',
      )
      // 无 src 的空 img 标签（<img> / <img />）与其余 img 残壳直接移除
      .replaceAll(RegExp(r'<img\b[^>]*>', caseSensitive: false), '')
      .replaceAll(RegExp(r'</?a\b[^>]*>', caseSensitive: false), '')
      .replaceAll(RegExp(r'</?div[^>]*>', caseSensitive: false), '')
      .replaceAll(RegExp(r'</?picture[^>]*>', caseSensitive: false), '')
      .replaceAll(RegExp(r'<source\b[^>]*/?>', caseSensitive: false), '')
      .replaceAll(RegExp(r'</?center[^>]*>', caseSensitive: false), '')
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n\n')
      .replaceAll(RegExp(r'</?p\b[^>]*>', caseSensitive: false), '\n\n')
      // 徽章/SVG 图片在排版中无意义，直接忽略
      .replaceAll(_ignoredImageRegExp, '');
  return _convertHtmlTags(stripped);
}

/// HTML 标签转 Markdown：
/// 块级 h1-h6 → `#` 标题；strong/b→加粗、em/i→斜体、del/s/strike→删除线；
/// u/mark/kbd/sub/sup/small/span/font 等无等价语法的剥壳保留文字。
String _convertHtmlTags(String md) {
  var text = md;
  // 块级标题：<h1>标题</h1> → # 标题（多行内容取首行）
  text = text.replaceAllMapped(
    RegExp(
      r'<h([1-6])\b[^>]*>([\s\S]*?)</h\1\s*>',
      caseSensitive: false,
    ),
    (m) {
      final level = int.parse(m.group(1)!);
      final inner =
          m.group(2)!.replaceAll(RegExp(r'<[^>]+>'), '').trim();
      return '\n\n${'#' * level} $inner\n\n';
    },
  );
  return text
      .replaceAllMapped(
        RegExp(r'<(strong|b)\b[^>]*>([\s\S]*?)</\1\s*>',
            caseSensitive: false),
        (m) => '**${m.group(2)!}**',
      )
      .replaceAllMapped(
        RegExp(r'<(em|i)\b[^>]*>([\s\S]*?)</\1\s*>', caseSensitive: false),
        (m) => '*${m.group(2)!}*',
      )
      .replaceAllMapped(
        RegExp(r'<(del|s|strike)\b[^>]*>([\s\S]*?)</\1\s*>',
            caseSensitive: false),
        (m) => '~~${m.group(2)!}~~',
      )
      .replaceAll(
        RegExp(
          r'</?(u|mark|kbd|sub|sup|small|span|font)\b[^>]*>',
          caseSensitive: false,
        ),
        '',
      );
}

/// 收集文档中按顺序出现的图片地址（Markdown 图片语法）。
List<String> collectImageUrls(String body) => RegExp(
      r'!\[[^\]]*\]\(([^)\s]+)\)',
    )
        .allMatches(body)
        .map((m) => m.group(1)!)
        .toList();

/// 估算阅读分钟数：正文按 300 字/分钟，代码块按 200 字符/分钟折算。
int estimateReadingMinutes(String body) {
  var codeChars = 0;
  var textChars = 0;
  var inFence = false;
  for (final line in body.split('\n')) {
    final t = line.trim();
    if (t.startsWith('```') || t.startsWith('~~~')) {
      inFence = !inFence;
      continue;
    }
    if (inFence) {
      codeChars += t.length;
    } else {
      textChars += t.replaceAll(RegExp(r'\s'), '').length;
    }
  }
  final minutes = textChars / 300 + codeChars / 200;
  return minutes < 1 ? 1 : minutes.ceil();
}

/// 标题 → GitHub 风格锚点：小写、去特殊字符、空格转连字符（保留 CJK）。
///
/// 必须开 `unicode: true`：否则 `\p{L}` 不被识别，整个字符类会退化，
/// 把正文字符全删光（历史 bug：站内 `#标题` 锚点因此永远匹配不上）。
String slugifyHeading(String text) => text
    .toLowerCase()
    .replaceAll(RegExp(r'[^\p{L}\p{N}\s-]', unicode: true), '')
    .trim()
    .replaceAll(RegExp(r'\s+'), '-');
