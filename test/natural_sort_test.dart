import 'package:flutter_test/flutter_test.dart';
import 'package:reader/src/notes/note_scanner.dart';

void main() {
  group('compareNatural 自然排序', () {
    test('无占位序号：chapter10 排在 chapter2 之后', () {
      final names = ['chapter10.md', 'chapter2.md', 'chapter1.md'];
      final sorted = names..sort(compareNatural);
      expect(sorted, ['chapter1.md', 'chapter2.md', 'chapter10.md']);
    });

    test('数字与文字混合段比较', () {
      final names = ['第2章.md', '第10章.md', '第1章.md'];
      final sorted = names..sort(compareNatural);
      expect(sorted, ['第1章.md', '第2章.md', '第10章.md']);
    });

    test('前导零按数值比较且顺序确定', () {
      final names = ['002-a', '10-b', '2-c', '02-d'];
      final sorted = names..sort(compareNatural);
      // 2/002/02 数值相同 → 长度小的在前，10 最后
      expect(sorted, ['2-c', '02-d', '002-a', '10-b']);
    });

    test('字母段大小写不敏感', () {
      final names = ['Beta', 'alpha', 'Gamma'];
      final sorted = names..sort(compareNatural);
      expect(sorted, ['alpha', 'Beta', 'Gamma']);
    });

    test('compareNaturalByName 按文件名比较（忽略目录前缀）', () {
      expect(
        compareNaturalByName('a/chapter9.md', 'b/chapter10.md'),
        isNegative,
      );
      expect(
        compareNaturalByName('x/y.md', 'x/y.md'),
        0,
      );
    });
  });
}
