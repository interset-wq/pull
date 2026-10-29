/// 代码大纲的符号提取（纯函数，便于单测）。
///
/// 正则启发式而非完整语法分析：目标是把「能跳的骨架」抽出来，
/// 覆盖笔记仓库里常见的语言即可；识别不到的符号不显示入口，
/// 不做半吊子的错位列表。
library;

/// 一个可跳转的代码符号。
class CodeSymbol {
  const CodeSymbol({
    required this.line,
    required this.name,
    required this.kind,
  });

  /// 1 基行号。
  final int line;

  final String name;

  /// `class` / `function` / `section`。
  final String kind;
}

/// 最多返回的符号数：超大生成文件不至于撑爆面板。
const int maxCodeSymbols = 500;

/// 从代码文本里抽取大纲符号；不认识的语言返回空列表。
List<CodeSymbol> extractCodeOutline(String content, String language) {
  final matchers = _matchersFor(language);
  if (matchers.isEmpty) return const [];
  final out = <CodeSymbol>[];
  final lines = content.split('\n');
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final trimmed = line.trimLeft();
    if (trimmed.isEmpty) continue;
    if (trimmed.startsWith('//') ||
        trimmed.startsWith('*') ||
        trimmed.startsWith('/*')) {
      continue;
    }
    for (final matcher in matchers) {
      final match = matcher.pattern.firstMatch(line);
      if (match == null) continue;
      final name = (match.group(matcher.nameGroup) ?? '').trim();
      if (name.isEmpty) continue;
      out.add(CodeSymbol(line: i + 1, name: name, kind: matcher.kind));
      if (out.length >= maxCodeSymbols) return out;
      break;
    }
  }
  return out;
}

class _Matcher {
  const _Matcher(this.pattern, this.nameGroup, this.kind);

  final RegExp pattern;
  final int nameGroup;
  final String kind;
}

const _class = 'class';
const _function = 'function';
const _section = 'section';

List<_Matcher> _matchersFor(String language) {
  switch (language) {
    case 'dart':
      return [
        _Matcher(
          RegExp(
            r'^\s*(?:abstract\s+|sealed\s+|base\s+|final\s+|interface\s+)?'
            r'(?:class|mixin|enum|extension)\s+(\w+)',
          ),
          1,
          _class,
        ),
        _Matcher(
          RegExp(
            r'^\s{0,4}(?:static\s+)?(?:Future<[^>]*>|Stream<[^>]*>|void|'
            r'String|int|bool|double|num|List<[^>]*>|Map<[^>]*>|Set<[^>]*>|'
            r'Widget|[A-Z]\w*(?:<[^>]*>)?)\s+(\w+)\s*\(',
          ),
          1,
          _function,
        ),
      ];
    case 'python':
      return [
        _Matcher(RegExp(r'^\s*class\s+(\w+)'), 1, _class),
        _Matcher(RegExp(r'^\s*(?:async\s+)?def\s+(\w+)'), 1, _function),
      ];
    case 'javascript':
    case 'typescript':
      return [
        _Matcher(
          RegExp(
            r'^\s*(?:export\s+(?:default\s+)?)?(?:abstract\s+)?'
            r'class\s+(\w+)',
          ),
          1,
          _class,
        ),
        _Matcher(
          RegExp(
            r'^\s*(?:export\s+(?:default\s+)?)?(?:async\s+)?function\s*\*?\s*'
            r'(\w+)',
          ),
          1,
          _function,
        ),
        _Matcher(
          RegExp(
            r'^\s*(?:export\s+)?const\s+(\w+)\s*=\s*(?:async\s*)?'
            r'(?:\([^)]*\)|\w+)\s*=>',
          ),
          1,
          _function,
        ),
        _Matcher(
          RegExp(r'^\s*(?:export\s+)?(?:interface|type|enum)\s+(\w+)'),
          1,
          _class,
        ),
      ];
    case 'java':
    case 'kotlin':
      return [
        _Matcher(
          RegExp(
            r'^\s*(?:(?:public|private|protected|internal|static|final|'
            r'abstract|open|sealed|data|enum)\s+)*'
            r'(?:class|interface|enum|object|record)\s+(\w+)',
          ),
          1,
          _class,
        ),
        _Matcher(
          RegExp(
            r'^\s*(?:(?:public|private|protected|internal|open|override|'
            r'suspend|inline|operator|infix|tailrec)\s+)*'
            r'fun\s+(?:<[^>]+>\s*)?(\w+)',
          ),
          1,
          _function,
        ),
        _Matcher(
          RegExp(
            r'^\s*(?:(?:public|private|protected|static|final|abstract|'
            r'synchronized|native|default)\s+)+'
            r'[\w<>\[\],.?\s]+\s+(\w+)\s*\(',
          ),
          1,
          _function,
        ),
      ];
    case 'go':
      return [
        _Matcher(
          RegExp(r'^\s*func\s+(?:\([^)]*\)\s*)?(\w+)'),
          1,
          _function,
        ),
        _Matcher(
          RegExp(r'^\s*type\s+(\w+)\s+(?:struct|interface)\b'),
          1,
          _class,
        ),
      ];
    case 'rust':
      return [
        _Matcher(
          RegExp(
            r'^\s*(?:pub(?:\([^)]*\))?\s+)?(?:async\s+)?(?:unsafe\s+)?'
            r'fn\s+(\w+)',
          ),
          1,
          _function,
        ),
        _Matcher(
          RegExp(
            r'^\s*(?:pub(?:\([^)]*\))?\s+)?'
            r'(?:struct|enum|trait|mod)\s+(\w+)',
          ),
          1,
          _class,
        ),
        _Matcher(
          RegExp(
            r'^\s*(?:pub(?:\([^)]*\))?\s+)?impl(?:<[^>]*>)?\s+(\w+)',
          ),
          1,
          _class,
        ),
      ];
    case 'c':
    case 'cpp':
      return [
        _Matcher(
          RegExp(r'^\s*(?:class|struct)\s+(\w+)'),
          1,
          _class,
        ),
        _Matcher(
          RegExp(
            r'^\s*(?:static\s+|inline\s+|extern\s+)*'
            r'(?:[A-Za-z_]\w*[\s*&]+)+([A-Za-z_]\w*)\s*\([^;]*\)\s*'
            r'(?:const\s*)?\{?\s*$',
          ),
          1,
          _function,
        ),
      ];
    case 'bash':
      return [
        _Matcher(
          RegExp(r'^\s*(?:function\s+)?(\w+)\s*\(\)\s*\{'),
          1,
          _function,
        ),
        _Matcher(RegExp(r'^\s*#{1,4}\s+(.+?)\s*$'), 1, _section),
      ];
    case 'yaml':
      return [
        _Matcher(RegExp(r'^([A-Za-z_][\w.-]*):'), 1, _section),
      ];
    case 'ini':
      return [
        _Matcher(RegExp(r'^\s*\[([^\]]+)\]'), 1, _section),
      ];
    default:
      return const [];
  }
}
