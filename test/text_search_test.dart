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
        final h = s.highlights.single;
        expect(s.text.substring(h.start, h.start + h.length), '关键词');
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
      final h = s.highlights.single;
      expect(s.text.substring(h.start, h.start + h.length), '关键词');
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

  group('多词 AND 检索', () {
    test('所有词都出现才算匹配', () {
      final hit = searchInText(
        relativePath: 'a',
        content: 'flutter 状态 管理',
        query: 'flutter 管理',
      );
      expect(hit, isNotNull);
      expect(hit!.matches, 2);
      expect(
        searchInText(
          relativePath: 'a',
          content: '只有 flutter',
          query: 'flutter 管理',
        ),
        isNull,
      );
    });

    test('摘要里每个词都有高亮区间', () {
      final r = searchInText(
        relativePath: 'a',
        content: '第一行 flutter 与 状态',
        query: 'flutter 状态',
      );
      final snippet = r!.snippets.single;
      final words = snippet.highlights
          .map((h) => snippet.text.substring(h.start, h.start + h.length))
          .toList();
      expect(words, containsAll(['flutter', '状态']));
    });

    test('全角空格与大小写', () {
      final r = searchInText(
        relativePath: 'a',
        content: 'Flutter　状态',
        query: 'FLUTTER　状态',
      );
      expect(r, isNotNull);
      expect(r!.matches, 2);
    });

    test('拆分查询词的纯函数', () {
      expect(splitSearchTerms('  Flutter  状态　管理 '),
          ['flutter', '状态', '管理']);
      expect(splitSearchTerms('   '), isEmpty);
    });
  });

  group('findTextMatches 文内查找', () {
    test('返回每处命中的偏移、行号与整行文本', () {
      const text = '# 标题\n第一行 关键词 在这里\n\n第二段 关键词\n';
      final matches = findTextMatches(text, '关键词');
      expect(matches.length, 2);
      expect(matches[0].line, 1);
      expect(matches[0].lineText, '第一行 关键词 在这里');
      expect(text.substring(matches[0].offset, matches[0].offset + 3), '关键词');
      expect(matches[1].line, 3);
    });

    test('大小写不敏感，空查询返回空列表', () {
      const text = 'Flutter\nflutter';
      expect(findTextMatches(text, 'FLUTTER').length, 2);
      expect(findTextMatches(text, '   '), isEmpty);
      expect(findTextMatches('', 'x'), isEmpty);
    });

    test('行号与 toc 的 line 同一坐标系（含 CRLF）', () {
      const text = '# 第一章\r\n正文\r\n## 第二章\r\n关键词\r\n';
      final matches = findTextMatches(text, '关键词');
      expect(matches.single.line, 3);
      expect(matches.single.lineText, '关键词');
    });
  });
}
