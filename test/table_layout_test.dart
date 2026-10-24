import 'package:flutter_test/flutter_test.dart';
import 'package:reader/src/notes/table_layout.dart';

void main() {
  group('detectTableLayout', () {
    test('无表格的文档 → wrap', () {
      expect(detectTableLayout('# 标题\n\n纯文本段落。'), TableLayout.wrap);
    });

    test('纯文本短表格 → wrap（换行铺满屏宽）', () {
      const md = '''
| 功能 | 说明 |
| --- | --- |
| 克隆 | 整仓克隆到本地 |
| 同步 | 启动时静默 pull |
''';
      expect(detectTableLayout(md), TableLayout.wrap);
    });

    test('长中文单元格仍 → wrap（CJK 可逐字断行）', () {
      const md = '''
| 项目 | 详细描述 |
| --- | --- |
| 阅读器 | 这是一个非常非常长的描述，用于验证中文单元格不会触发横滚策略 |
''';
      expect(detectTableLayout(md), TableLayout.wrap);
    });

    test('超过 5 列 → scroll', () {
      const md = '''
| a | b | c | d | e | f |
| --- | --- | --- | --- | --- | --- |
| 1 | 2 | 3 | 4 | 5 | 6 |
''';
      expect(detectTableLayout(md), TableLayout.scroll);
    });

    test('单元格含长 URL → scroll', () {
      const md = '''
| 链接 |
| --- |
| https://gitcode.com/interset-wq/reader/releases |
''';
      expect(detectTableLayout(md), TableLayout.scroll);
    });

    test('单元格含长行内代码 → scroll', () {
      const md = '''
| API |
| --- |
| `repository.clone(checkoutBranch)` |
''';
      expect(detectTableLayout(md), TableLayout.scroll);
    });

    test('代码围栏内的竖线不算表格 → wrap', () {
      const md = '''
| 功能 | 说明 |
| --- | --- |
| a | b |

```bash
echo "not | a | table"
''';
      expect(detectTableLayout(md), TableLayout.wrap);
    });

    test('仅围栏内出现伪表格 → wrap', () {
      const md = '''
```text
| a | b | c | d | e | f | g |
| 1 | 2 | 3 | 4 | 5 | 6 | 7 |
```
''';
      expect(detectTableLayout(md), TableLayout.wrap);
    });

    test('短行内代码不触发横滚 → wrap', () {
      const md = '''
| 文件 | 大小 |
| --- | --- |
| `main.dart` | 12 KB |
''';
      expect(detectTableLayout(md), TableLayout.wrap);
    });
  });
}
