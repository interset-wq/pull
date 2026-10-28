import 'package:flutter_test/flutter_test.dart';
import 'package:reader/src/search/text_search.dart';

void main() {
  group('searchInText 计数与摘要', () {
    test('大小写不敏感并统计全部命中', () {
      final r = searchInText(
        relativePath: 'a.md',
        content: 'Flutter 很好用\nflutter 也不错\n其他',
        query: 'FLUTTER',
      );
      expect(r, isNotNull);
      expect(r!.matches, 2);
      expect(r.snippets.length, 2);
      expect(r.snippets.first.line, 0);
      expect(r.snippets.last.line, 1);
    });

    test('中文直接匹配', () {
      final r = searchInText(
        relativePath: 'a.md',
        content: '# 笔记\n今天记录一条笔记',
        query: '笔记',
      );
      expect(r!.matches, 2);
      expect(r.snippets.first.text, contains('笔记'));
    });

    test('没有命中返回 null，空查询返回 null', () {
      expect(
        searchInText(relativePath: 'a', content: 'abc', query: 'zzz'),
        isNull,
      );
      expect(
        searchInText(relativePath: 'a', content: 'abc', query: '   '),
        isNull,
      );
    });

    test('同一行多处命中只产生一条摘要，但计数照算', () {
      final r = searchInText(
        relativePath: 'a',
        content: 'a a a a',
        query: 'a',
      );
      expect(r!.matches, 4);
      expect(r.snippets.length, 1);
    });

    test('摘要数量上限，且偏移能精确框出命中', () {
      final content = List.generate(10, (i) => '行$i 关键词').join('\n');
      final r = searchInText(
        relativePath: 'a',
        content: content,
        query: '关键词',
        maxSnippets: 2,
      );
      expect(r!.matches, 10);
      expect(r.snippets.length, 2);
      for (final s in r.snippets) {
        expect(
          s.text.substring(s.matchStart, s.matchStart + s.matchLength),
          '关键词',
        );
      }
    });

    test('超长行围绕命中截断，命中仍在片段内', () {
      final prefix = 'x' * 200;
      final suffix = 'y' * 200;
      final content = '$prefix关键词$suffix';
      final r = searchInText(
        relativePath: 'a',
        content: content,
        query: '关键词',
      );
      final s = r!.snippets.single;
      expect(s.text.length, lessThan(120));
      expect(
        s.text.substring(s.matchStart, s.matchStart + s.matchLength),
        '关键词',
      );
    });

    test('CRLF 行尾不影响片段与行号', () {
      final r = searchInText(
        relativePath: 'a',
        content: '第一行\r\n第二行 命中\r\n第三行',
        query: '命中',
      );
      expect(r!.snippets.single.line, 1);
      expect(r.snippets.single.text.contains('\r'), isFalse);
    });
  });
}
