import 'package:flutter_test/flutter_test.dart';
import 'package:reader/src/notes/markdown_source.dart';

/// 阅读时长估算与标题锚点（从阅读页拆出的纯函数）。
void main() {
  test('estimateReadingMinutes rounds up with a one-minute floor', () {
    expect(estimateReadingMinutes(''), 1);
    expect(estimateReadingMinutes('短句'), 1);
    expect(estimateReadingMinutes('字' * 600), 2);
    // 代码按 200 字符/分钟折算：600 个字符 = 3 分钟
    final code = '```\n${'x' * 600}\n```';
    expect(estimateReadingMinutes(code), 3);
  });

  test('slugifyHeading keeps CJK and dashes spaces', () {
    expect(slugifyHeading('Hello World'), 'hello-world');
    expect(slugifyHeading('第一 章：入门'), '第一-章入门');
    expect(slugifyHeading('  A  B  '), 'a-b');
    expect(slugifyHeading('C++ / Dart'), 'c-dart');
  });
}
