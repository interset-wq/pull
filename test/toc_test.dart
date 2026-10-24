import 'package:flutter_test/flutter_test.dart';
import 'package:reader/src/notes/toc.dart';

void main() {
  group('extractToc 围栏判定（CommonMark）', () {
    test('普通围栏内的 # 行不进 TOC', () {
      final toc = extractToc('# 标题\n```python\n# 注释\n```\n## 二级\n');
      expect(toc.map((e) => e.text), ['标题', '二级']);
    });

    test('行内三反引号（```text```）不是围栏，不翻转状态', () {
      // 复现 llm-universe C2.md L731：代码块内的行内代码注释
      const md = '## 2.3 节\n'
          '```python\n'
          '# 使用分隔符(指令内容，使用 ``` 来分隔指令和待总结的内容)\n'
          'print(1)\n'
          '```\n'
          '### 2.3.1 小节\n';
      final toc = extractToc(md);
      expect(toc.map((e) => e.text), ['2.3 节', '2.3.1 小节']);
    });

    test('开栏 info string 含反引号（```a```）不作为围栏开启', () {
      const md = '```text 这不是围栏```\n# 真标题\n';
      final toc = extractToc(md);
      expect(toc.map((e) => e.text), ['真标题']);
    });

    test('闭栏长度不小于开栏（```` 包住 ```）', () {
      const md = '````\n```\n# 假标题\n````\n## 真二级\n';
      final toc = extractToc(md);
      expect(toc.map((e) => e.text), ['真二级']);
    });

    test('波浪线围栏与反引号围栏互不关闭', () {
      const md = '~~~\n```\n# 假标题\n~~~\n## 真二级\n';
      final toc = extractToc(md);
      expect(toc.map((e) => e.text), ['真二级']);
    });

    test('缩进的围栏同样生效（trimLeft 后判定）', () {
      const md = '# a\n  ```python\n# 注释\n  ```\n## b\n';
      final toc = extractToc(md);
      expect(toc.map((e) => e.text), ['a', 'b']);
    });

    test('闭栏后允许尾随空白，带文字的反引号行不是闭栏', () {
      const md = '```python\n``` 不是闭栏\n```\n## after\n';
      final toc = extractToc(md);
      expect(toc.map((e) => e.text), ['after']);
    });

    test('CRLF 行尾（Windows 仓库）围栏正常开闭', () {
      const md = '# a\r\n```json\r\n# 注释\r\n```\r\n## b\r\n'
          '```python\r\n# 行内```陷阱```\r\n```\r\n### c\r\n';
      final toc = extractToc(md);
      expect(toc.map((e) => e.text), ['a', 'b', 'c']);
    });

    test('setext 标题（=== H1 / --- H2）按 markdown_widget 口径识别', () {
      const md = '大标题\n=====\n正文\n\n小标题\n---\n正文\n## atx\n';
      final toc = extractToc(md);
      expect(toc.map((e) => e.text), ['大标题', '小标题', 'atx']);
      expect(toc.map((e) => e.level), [1, 2, 2]);
      expect(toc.map((e) => e.line), [0, 4, 7]);
    });

    test('单独的 --- 与列表后的 --- 是分隔线不是 setext 标题', () {
      const md = '- item\n---\n\n# 真标题\n';
      final toc = extractToc(md);
      expect(toc.map((e) => e.text), ['真标题']);
    });
  });
}
