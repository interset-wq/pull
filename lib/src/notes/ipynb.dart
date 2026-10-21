import 'dart:convert';

/// Jupyter Notebook（.ipynb）→ Markdown 的轻量转换。
///
/// 只做展示级转换：markdown/code/raw 单元转为对应 Markdown；
/// 代码单元的输出保留 stdout/stderr 文本与 execute_result 的 text/plain，
/// HTML/图片等富输出以占位提示代替，不做渲染。
class IpynbConverter {
  /// 转换为 Markdown 源文本；解析失败时抛 [FormatException]。
  static String toMarkdown(String source) {
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
          out.add('```$lang\n$src\n```');
          final outputMd = _outputsToMarkdown(cell['outputs']);
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

  static String _outputsToMarkdown(Object? outputs) {
    if (outputs is! List) return '';
    final lines = <String>[];
    for (final output in outputs) {
      if (output is! Map<String, dynamic>) continue;
      final type = output['output_type'] as String?;
      switch (type) {
        case 'stream':
          final text = _joinSource(output['text']);
          if (text.isNotEmpty) lines.add('```\n$text\n```');
        case 'execute_result' || 'display_data':
          final data = output['data'];
          if (data is Map<String, dynamic>) {
            final plain = data['text/plain'];
            final text = _joinSource(plain);
            if (text.isNotEmpty) {
              lines.add('```\n$text\n```');
            } else if (data.containsKey('image/png')) {
              lines.add('*[图片输出，暂不支持显示]*');
            } else if (data.containsKey('text/html')) {
              lines.add('*[HTML 输出，暂不支持显示]*');
            }
          }
        case 'error':
          final ename = output['ename']?.toString() ?? 'Error';
          final evalue = output['evalue']?.toString() ?? '';
          lines.add('> [!WARNING]\n> **$ename**: $evalue');
      }
    }
    return lines.join('\n\n');
  }
}
