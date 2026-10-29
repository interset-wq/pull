import 'dart:convert';
import 'dart:typed_data';

/// Notebook 富输出里的内嵌图片（base64）暂存。
///
/// 不落盘：图片随 notebook 打开即时解码，体积可观但生命周期短；落盘还要
/// 额外处理缓存目录的统计与清理。按**内容哈希**寻址，同一张图重复出现
/// （例如同一 notebook 多次打开）直接复用。
///
/// Markdown 里只留 `pullread-ipynb://<hash>.<ext>` 这样的短引用，
/// 不把 base64 塞进正文——否则复制全文、文内查找、TOC 行号都会被它污染。
class IpynbImageStore {
  IpynbImageStore._();

  static const scheme = 'pullread-ipynb://';

  /// 内存上限：100 张百 KB 级的图表也才 10MB，64MB 足够兜住极端 notebook。
  static const _maxBytes = 64 * 1024 * 1024;

  /// 插入顺序即最近使用顺序（命中不重复插入，淘汰按插入序近似 LRU）。
  static final _images = <String, Uint8List>{};
  static int _bytes = 0;

  /// 存入一张图片，返回可直接写进 Markdown 的引用地址。
  static String put(Uint8List bytes, {required String ext}) {
    final key = '${_hash(bytes)}.$ext';
    final existed = _images.remove(key);
    if (existed != null) _bytes -= existed.length;
    _images[key] = bytes;
    _bytes += bytes.length;
    while (_bytes > _maxBytes && _images.isNotEmpty) {
      final oldest = _images.keys.first;
      _bytes -= _images.remove(oldest)!.length;
    }
    return '$scheme$key';
  }

  /// 解析引用地址；不是 notebook 图片或已被淘汰时返回 null。
  static Uint8List? bytesFor(String url) {
    if (!url.startsWith(scheme)) return null;
    return _images[url.substring(scheme.length)];
  }

  /// 是不是 notebook 内嵌图片引用（图库、图片加载器据此分流）。
  static bool isIpynbImage(String url) => url.startsWith(scheme);

  /// 两个 32 位哈希拼成 64 位，内容寻址、稳定且碰撞概率极低。
  static String _hash(Uint8List bytes) {
    var h1 = 0x811c9dc5;
    var h2 = 5381;
    for (final b in bytes) {
      h1 = ((h1 ^ b) * 0x01000193) & 0xFFFFFFFF;
      h2 = ((h2 * 33) + b) & 0xFFFFFFFF;
    }
    return '${h1.toRadixString(16).padLeft(8, '0')}'
        '${h2.toRadixString(16).padLeft(8, '0')}';
  }
}

/// 把 pandas 之类的简单 `<table>` 降级成 Markdown 表格。
///
/// 只处理「规整」的表（无 rowspan/colspan、行数 ≤100、列数 ≤30）；
/// 复杂表格返回 null，调用方回退到 `text/plain` 或占位提示，
/// 不做半吊子的错位渲染。
String? htmlTableToMarkdown(String html) {
  if (html.contains('rowspan') || html.contains('colspan')) return null;
  final tableMatch =
      RegExp(r'<table[\s\S]*?</table>', caseSensitive: false).firstMatch(html);
  if (tableMatch == null) return null;
  final rows = RegExp(r'<tr[\s\S]*?</tr>', caseSensitive: false)
      .allMatches(tableMatch.group(0)!)
      .map((m) => m.group(0)!)
      .toList();
  if (rows.isEmpty) return null;
  final parsed = <List<String>>[];
  for (final row in rows) {
    final cells = RegExp(r'<t[hd][^>]*>([\s\S]*?)</t[hd]>', caseSensitive: false)
        .allMatches(row)
        .map((m) => _cellText(m.group(1)!))
        .toList();
    if (cells.isNotEmpty) parsed.add(cells);
  }
  if (parsed.isEmpty) return null;
  final width = parsed.map((r) => r.length).reduce((a, b) => a > b ? a : b);
  if (width == 0 || width > 30 || parsed.length > 100) return null;
  String line(List<String> cells) {
    final padded = [
      ...cells,
      for (var i = cells.length; i < width; i++) '',
    ];
    return '| ${padded.join(' | ')} |';
  }

  final out = StringBuffer()
    ..writeln(line(parsed.first))
    ..writeln('| ${List.filled(width, '---').join(' | ')} |');
  for (final row in parsed.skip(1)) {
    out.writeln(line(row));
  }
  return out.toString().trimRight();
}

String _cellText(String cell) {
  var text = cell
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'<[^>]+>'), ' ');
  text = text
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&amp;', '&');
  text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  // 表格分隔符必须转义，否则一列会被拆成两列
  return text.replaceAll('|', r'\|');
}

/// base64 历史数据偶发换行与填充差异，统一清洗后再解码。
Uint8List? decodeBase64Payload(Object? raw) {
  final text = switch (raw) {
    String s => s,
    List l => l.map((e) => e.toString()).join(),
    _ => null,
  };
  if (text == null || text.isEmpty) return null;
  try {
    return base64Decode(text.replaceAll(RegExp(r'\s'), ''));
  } on FormatException {
    return null;
  }
}
