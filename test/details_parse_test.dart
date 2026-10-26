import 'package:flutter_test/flutter_test.dart';
import 'package:markdown/markdown.dart' as m;
import 'package:reader/src/notes/details_syntax.dart';

/// 折叠块解析测试：DetailsBlockSyntax 拦截 `<details>` 块，产出
/// Element(tag: 'details') 供 markdown_viewer 的自定义节点渲染。
m.Document doc() => m.Document(
      extensionSet: m.ExtensionSet.gitHubFlavored,
      blockSyntaxes: [DetailsBlockSyntax()],
    );

void main() {
  group('DetailsBlockSyntax 解析', () {
    test('多行写法：产出 details 元素 + summary + 内部 Markdown 块', () {
      final nodes = doc().parse('''
<details>
<summary>点我展开</summary>

内容段落一

```dart
print('代码块');
```

</details>

后面的正文
''');
      final details = nodes.whereType<m.Element>().where((e) => e.tag == 'details').toList();
      expect(details, hasLength(1), reason: 'details 块应产出 details 元素');
      final summary = details.first.children!
          .whereType<m.Element>()
          .firstWhere((e) => e.tag == 'summary');
      expect(summary.textContent, '点我展开');
      final tags = details.first.children!.whereType<m.Element>().map((e) => e.tag).toList();
      expect(tags, containsAll(['p', 'pre']), reason: '内部 Markdown（段落/代码块）应正常解析');
      expect(details.first.attributes.containsKey('open'), isFalse);
      // details 之后的内容正常解析
      expect(nodes.last.textContent, contains('后面的正文'));
    });

    test('单行 summary 写法（notes/interview 实际用法）', () {
      final nodes = doc().parse('''
<details><summary>答案</summary>

回答内容

</details>
''');
      final details = nodes.whereType<m.Element>().firstWhere((e) => e.tag == 'details');
      final summary = details.children!.whereType<m.Element>().firstWhere((e) => e.tag == 'summary');
      expect(summary.textContent, '答案');
      expect(details.children!.any((e) => e.textContent.contains('回答内容')), isTrue);
    });

    test('open 属性透传', () {
      final nodes = doc().parse('<details open>\n<summary>s</summary>\n内容\n</details>\n');
      final details = nodes.whereType<m.Element>().firstWhere((e) => e.tag == 'details');
      expect(details.attributes['open'], 'open');
    });

    test('嵌套 details', () {
      final nodes = doc().parse('''
<details><summary>外层</summary>

<details><summary>内层</summary>

内层内容

</details>

</details>
''');
      final outer = nodes.whereType<m.Element>().firstWhere((e) => e.tag == 'details');
      final inner = outer.children!
          .whereType<m.Element>()
          .where((e) => e.tag == 'details')
          .toList();
      expect(inner, hasLength(1), reason: '嵌套 details 应正确配对');
      expect(inner.first.textContent, contains('内层内容'));
    });

    test('summary 之外的属性（如 <details open>）不吞正文', () {
      final nodes = doc().parse('''
正文前

<details>
<summary>答案</summary>
内容A
</details>

正文后
''');
      expect(nodes.first.textContent, contains('正文前'));
      expect(nodes.last.textContent, contains('正文后'));
    });
  });
}
