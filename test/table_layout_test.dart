import 'package:flutter_test/flutter_test.dart';
import 'package:reader/src/notes/table_layout.dart';

void main() {
  group('estimateTableNaturalWidth', () {
    test('无表格的文档 → 0', () {
      expect(estimateTableNaturalWidth('# 标题\n\n纯文本段落。', 16), 0);
    });

    test('代码围栏内的伪表格被忽略 → 0', () {
      const md = '''
```text
| a | b | c | d | e | f | g |
| 1 | 2 | 3 | 4 | 5 | 6 | 7 |
```
''';
      expect(estimateTableNaturalWidth(md, 16), 0);
    });

    test('短中文表格宽度有限', () {
      const md = '''
| 功能 | 说明 |
| --- | --- |
| 克隆 | 整仓克隆到本地 |
| 同步 | 启动时静默 pull |
''';
      final w = estimateTableNaturalWidth(md, 16);
      // 两列：每列最宽单元格 + 内边距/边框；粗估 2*(6*16+17) ≈ 230
      expect(w, greaterThan(150));
      expect(w, lessThan(400));
    });

    test('长中文表格宽度远超短表', () {
      const md = '''
| 题号 | 问题 | 要点答案 |
| --- | --- | --- |
| 1 | 自我介绍 | 结构 = 个人技能优势 + 工作背景 + 经验亮点。按岗位准备 3 个版本：功能/接口/性能/自动化/鸿蒙各一 |
''';
      final w = estimateTableNaturalWidth(md, 16);
      // 答案列约 50 个 CJK 字符 ≈ 800px
      expect(w, greaterThan(700));
    });

    test('多个表格取最宽的一个', () {
      const md = '''
| a | b |
| --- | --- |
| 1 | 2 |

正文分隔。

| 题号 | 问题 | 要点答案 |
| --- | --- | --- |
| 1 | 自我介绍 | 结构 = 个人技能优势 + 工作背景 + 经验亮点。按岗位准备 3 个版本：功能/接口/性能/自动化/鸿蒙各一 |
''';
      final w = estimateTableNaturalWidth(md, 16);
      expect(w, greaterThan(700));
    });

    test('字号越大估算宽度越大', () {
      const md = '''
| 功能 | 说明 |
| --- | --- |
| 克隆 | 整仓克隆到本地 |
''';
      expect(estimateTableNaturalWidth(md, 18) ,
          greaterThan(estimateTableNaturalWidth(md, 14)));
    });

    test('行内代码按 0.6em 估宽', () {
      const md = '''
| 命令 |
| --- |
| `cat/more/less/grep/head/tail/find/ls/pwd` |
''';
      // 42 字符（含反引号）* 0.6 * 16 ≈ 403 + 内边距/边框 17 ≈ 420
      final w = estimateTableNaturalWidth(md, 16);
      expect(w, closeTo(420, 5));
    });
  });
}
