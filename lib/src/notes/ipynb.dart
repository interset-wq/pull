import 'dart:convert';
import 'dart:typed_data';

import 'ipynb_images.dart';

/// Jupyter Notebook（.ipynb）→ Markdown 的轻量转换。
///
/// 展示级转换：markdown/code/raw 单元转为对应 Markdown；代码单元的输出保留
/// stdout/stderr 文本、text/plain，并尽量显示富输出——
/// - `image/png|jpeg|gif|svg`：解码后存进 [IpynbImageStore]，正文里只留
///   `pullread-ipynb://…` 短引用（复制全文/文内查找不会被 base64 污染）；
///   matplotlib 的 `<Figure ...>` 文本占位在有图时直接丢弃；
/// - `text/html` 里的简单表格降级成 Markdown 表格（pandas `df.head()`）；
///   解析不了就回退 text/plain，再不行给占位提示。
class IpynbConverter {
  /// 转换为 Markdown 源文本；解析失败时抛 [FormatException]。
  ///
  /// [includeImages] 为 false 时跳过内嵌图片（正文检索只需文字）：
  /// 不解 base64、不占内存，也不会把图片引用当成可搜索文本。
  static String toMarkdown(String source, {bool includeImages = true}) {
    final Object? json;
    try {
      json = jsonDecode(source);
    } on FormatException catch (e) {
      throw FormatException('无法解析 .ipynb JSON: ${e.message}');
    }
    if (json is! Map<String, dynamic> || json['cells'] is! List) {
      throw const FormatException('.ipynb 结构无效：缺少 cells');
    }
    final cells = json['cells'] as List;
    final out = <String>[];
    for (final cell in cells) {
      if (cell is! Map<String, dynamic>) continue;
      final type = cell['cell_type'] as String?;
      final src = _joinSource(cell['source']);
      switch (type) {
        case 'markdown':
          if (src.isNotEmpty) out.add(src);
        case 'code':
          final lang = _cellLanguage(cell, json);
          out.add(_fence(src, lang));
          final outputMd = _outputsToMarkdown(cell['outputs'], includeImages: includeImages);
          if (outputMd.isNotEmpty) out.add(outputMd);
        case 'raw':
          if (src.isNotEmpty) out.add(src);
      }
    }
    return out.join('\n\n');
  }

  static String _cellLanguage(
    Map<String, dynamic> cell,
    Map<String, dynamic> notebook,
  ) {
    final metadata = cell['metadata'];
    if (metadata is Map<String, dynamic>) {
      final langInfo = metadata['language_info'];
      if (langInfo is Map<String, dynamic> && langInfo['name'] is String) {
        return langInfo['name'] as String;
      }
    }
    // 回退到 notebook 级别语言
    final meta = notebook['metadata'];
    if (meta is Map<String, dynamic>) {
      final langInfo = meta['language_info'];
      if (langInfo is Map<String, dynamic> && langInfo['name'] is String) {
        return langInfo['name'] as String;
      }
    }
    return '';
  }

  /// source 可能是 string 或 string[]（每行含尾部 \n）。
  static String _joinSource(Object? source) {
    if (source is String) return source;
    if (source is List) {
      return source.map((e) => e.toString()).join();
    }
    return '';
  }

  static String _outputsToMarkdown(
    Object? outputs, {
    required bool includeImages,
  }) {
    if (outputs is! List) return '';
    final blocks = <String>[];
    for (final output in outputs) {
      if (output is! Map<String, dynamic>) continue;
      final type = output['output_type'] as String?;
      switch (type) {
        case 'stream':
          final text = _joinSource(output['text']);
          if (text.isNotEmpty) blocks.add(_fence(text));
        case 'execute_result' || 'display_data':
          final data = output['data'];
          if (data is Map<String, dynamic>) {
            final image = includeImages ? _imageMarkdown(data) : null;
            if (image != null) {
              blocks.add(image);
              continue;
            }
            final table = _htmlTableMarkdown(data['text/html']);
            if (table != null) {
              blocks.add(table);
              continue;
            }
            final plain = _joinSource(data['text/plain']);
            if (plain.isNotEmpty) {
              blocks.add(_fence(plain));
            } else if (data.containsKey('text/html')) {
              blocks.add('*[HTML 输出，暂不支持显示]*');
            }
          }
        case 'error':
          final ename = output['ename']?.toString() ?? 'Error';
          final evalue = output['evalue']?.toString() ?? '';
          blocks.add('> [!WARNING]\n> **$ename**: $evalue');
      }
    }
    return blocks.join('\n\n');
  }

  /// 围栏代码块：文本自带的换行不重复追加，避免正文里多出空行。
  static String _fence(String text, [String lang = '']) {
    final body = text.endsWith('\n') ? text : '$text\n';
    return '```$lang\n$body```';
  }

  /// 内嵌图片：优先位图（base64），svg 输出是文本。
  /// 返回 Markdown 图片语法；没有图片返回 null。
  static String? _imageMarkdown(Map<String, dynamic> data) {
    for (final (mime, ext) in _imageTypes) {
      final raw = data[mime];
      if (raw == null) continue;
      final Uint8List? bytes;
      if (mime == 'image/svg+xml') {
        final text = _joinSource(raw);
        bytes = text.isEmpty ? null : Uint8List.fromList(utf8.encode(text));
      } else {
        bytes = decodeBase64Payload(raw);
      }
      if (bytes == null || bytes.isEmpty) continue;
      final url = IpynbImageStore.put(bytes, ext: ext);
      return '![notebook 输出图]($url)';
    }
    return null;
  }

  static const _imageTypes = [
    ('image/png', 'png'),
    ('image/jpeg', 'jpg'),
    ('image/gif', 'gif'),
    ('image/svg+xml', 'svg'),
  ];

  /// `text/html` 可能是 string 或 string[]；只有能降级成表格才返回内容。
  static String? _htmlTableMarkdown(Object? html) {
    final text = _joinSource(html);
    if (text.isEmpty || !text.contains('<table')) return null;
    return htmlTableToMarkdown(text);
  }
}
