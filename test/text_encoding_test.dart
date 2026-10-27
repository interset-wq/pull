import 'dart:convert';

import 'package:fast_gbk/fast_gbk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader/src/utils/text_encoding.dart';

void main() {
  test('UTF-8 正常解码', () {
    final bytes = utf8.encode('第一章 起始\n正文内容');
    expect(decodeTextBytes(bytes), '第一章 起始\n正文内容');
  });

  test('UTF-8 BOM 被去除', () {
    final bytes = [0xEF, 0xBB, 0xBF, ...utf8.encode('标题')];
    expect(decodeTextBytes(bytes), '标题');
  });

  test('GBK 中文自动回退解码', () {
    final bytes = ascii.encode('name=') + const [0xC4, 0xE3, 0xBA, 0xC3]; // "你好" 的 GBK 编码
    expect(decodeTextBytes(bytes), 'name=你好');
  });

  test('GBK 长文（小说场景）', () {
    const text = '第三百二十章 故人重逢\n\n他推门而入，屋里灯还亮着。';
    final bytes = latin1.encode('x') + gbk.encode(text);
    expect(decodeTextBytes(bytes).substring(1), text);
  });
}
