import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader/src/notes/ipynb.dart';
import 'package:reader/src/notes/ipynb_images.dart';

void main() {
  test('converts markdown / code / raw cells', () {
    final md = IpynbConverter.toMarkdown(
      _notebook([
        _cell('markdown', ['# 标题\n', '正文']),
        _cell('code', ['print(1)']),
        _cell('raw', ['原样']),
      ]),
    );
    expect(md, contains('# 标题'));
    expect(md, contains('```python\nprint(1)\n```'));
    expect(md, contains('原样'));
  });

  test('renders stream and execute_result text outputs', () {
    final md = IpynbConverter.toMarkdown(
      _notebook([
        _cell('code', ['print("hi")'], outputs: [
          {
            'output_type': 'stream',
            'name': 'stdout',
            'text': ['hi\n'],
          },
          {
            'output_type': 'execute_result',
            'data': {'text/plain': ['42']},
          },
        ]),
      ]),
    );
    expect(md, contains('```\nhi\n```'));
    expect(md, contains('```\n42\n```'));
  });

  test('inlines png output as a short reference, not base64', () {
    final bytes = utf8.encode('fake-png-bytes');
    final b64 = base64Encode(bytes);
    final md = IpynbConverter.toMarkdown(
      _notebook([
        _cell('code', ['plt.plot()'], outputs: [
          {
            'output_type': 'display_data',
            'data': {'image/png': b64},
          },
        ]),
      ]),
    );
    expect(md, contains('pullread-ipynb://'));
    expect(md, isNot(contains(b64)), reason: 'base64 不能进正文');
    final url = RegExp(r'!\[[^\]]*\]\((pullread-ipynb://[^)]+)\)')
        .firstMatch(md)!
        .group(1)!;
    expect(IpynbImageStore.bytesFor(url), bytes);
  });

  test('prefers the image over matplotlib figure placeholder text', () {
    final b64 = base64Encode(utf8.encode('chart'));
    final md = IpynbConverter.toMarkdown(
      _notebook([
        _cell('code', ['plt.plot()'], outputs: [
          {
            'output_type': 'execute_result',
            'data': {
              'text/plain': ['<Figure size 640x480 with 1 Axes>'],
              'image/png': b64,
            },
          },
        ]),
      ]),
    );
    expect(md, contains('pullread-ipynb://'));
    expect(md, isNot(contains('<Figure size')), reason: '有图就不再显示占位文本');
  });

  test('search conversion skips embedded images', () {
    final b64 = base64Encode(utf8.encode('chart'));
    final md = IpynbConverter.toMarkdown(
      _notebook([
        _cell('code', ['plt.plot()'], outputs: [
          {
            'output_type': 'display_data',
            'data': {'image/png': b64},
          },
        ]),
      ]),
      includeImages: false,
    );
    expect(md, isNot(contains('pullread-ipynb://')));
    expect(md, isNot(contains(b64)));
  });

  test('degrades a simple html table to markdown', () {
    final md = IpynbConverter.toMarkdown(
      _notebook([
        _cell('code', ['df.head()'], outputs: [
          {
            'output_type': 'execute_result',
            'data': {
              'text/html': [
                '<table border="1" class="dataframe">\n',
                '<thead><tr><th>name</th><th>count</th></tr></thead>\n',
                '<tbody><tr><td>a|b</td><td>3</td></tr></tbody>\n',
                '</table>',
              ],
              'text/plain': ['  name count\n0  a|b 3'],
            },
          },
        ]),
      ]),
    );
    expect(md, contains('| name | count |'));
    expect(md, contains('| --- | --- |'));
    expect(md, contains(r'a\|b'), reason: '单元格里的竖线要转义');
    expect(md, isNot(contains('text/plain')), reason: '表格优先于纯文本输出');
  });

  test('falls back to text/plain for a complex table', () {
    final md = IpynbConverter.toMarkdown(
      _notebook([
        _cell('code', ['df'], outputs: [
          {
            'output_type': 'execute_result',
            'data': {
              'text/html': [
                '<table><tr><th colspan="2">merged</th></tr></table>',
              ],
              'text/plain': ['merged'],
            },
          },
        ]),
      ]),
    );
    expect(md, contains('```\nmerged\n```'));
  });

  test('renders error output as a warning block', () {
    final md = IpynbConverter.toMarkdown(
      _notebook([
        _cell('code', ['1/0'], outputs: [
          {
            'output_type': 'error',
            'ename': 'ZeroDivisionError',
            'evalue': 'division by zero',
          },
        ]),
      ]),
    );
    expect(md, contains('> [!WARNING]'));
    expect(md, contains('ZeroDivisionError'));
  });

  test('rejects invalid notebooks', () {
    expect(() => IpynbConverter.toMarkdown('not json'),
        throwsA(isA<FormatException>()));
    expect(() => IpynbConverter.toMarkdown('{"cells": 1}'),
        throwsA(isA<FormatException>()));
  });

  test('htmlTableToMarkdown handles empty and oversized tables', () {
    expect(htmlTableToMarkdown('<div>no table</div>'), isNull);
    expect(htmlTableToMarkdown('<table></table>'), isNull);
  });
}

String _notebook(List<Map<String, dynamic>> cells) => jsonEncode({
      'cells': cells,
      'metadata': {
        'language_info': {'name': 'python'},
      },
      'nbformat': 4,
    });

Map<String, dynamic> _cell(
  String type,
  List<String> source, {
  List<Map<String, dynamic>>? outputs,
}) =>
    {
      'cell_type': type,
      'source': source,
      'outputs': ?outputs,
    };
