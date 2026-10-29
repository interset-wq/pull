import 'package:flutter_test/flutter_test.dart';
import 'package:reader/src/notes/code_outline.dart';

/// 代码大纲的符号提取：各语言的常见声明都要能认出来，注释行要跳过。
void main() {
  test('dart classes, methods and top-level functions', () {
    const code = '''
class Foo {
  void bar() {}

  Future<void> baz() async {}
}

enum Color { red }

void topLevel() {}

// class Fake {}
''';
    final symbols = extractCodeOutline(code, 'dart');
    final names = symbols.map((s) => s.name).toList();
    expect(names, containsAll(['Foo', 'bar', 'baz', 'Color', 'topLevel']));
    expect(names, isNot(contains('Fake')), reason: '注释行不产出符号');
    expect(symbols.firstWhere((s) => s.name == 'Foo').kind, 'class');
    expect(symbols.firstWhere((s) => s.name == 'Foo').line, 1);
  });

  test('python classes and defs', () {
    const code = '''
class Model:
    def fit(self):
        pass

async def load():
    pass
''';
    final symbols = extractCodeOutline(code, 'python');
    expect(symbols.map((s) => s.name), ['Model', 'fit', 'load']);
    expect(symbols[0].kind, 'class');
    expect(symbols[1].kind, 'function');
  });

  test('javascript classes, functions and arrow consts', () {
    const code = '''
export class Store {}
export function create() {}
const handler = async (event) => {};
interface Props {}
''';
    final names =
        extractCodeOutline(code, 'javascript').map((s) => s.name).toList();
    expect(names, containsAll(['Store', 'create', 'handler', 'Props']));
  });

  test('go funcs and types', () {
    const code = '''
func main() {}
func (s *Server) Start() {}
type Config struct {
''';
    final names = extractCodeOutline(code, 'go').map((s) => s.name).toList();
    expect(names, containsAll(['main', 'Start', 'Config']));
  });

  test('rust fns, types and impls', () {
    const code = '''
pub fn run() {}
struct App {}
impl App {
    fn new() {}
}
''';
    final names = extractCodeOutline(code, 'rust').map((s) => s.name).toList();
    expect(names, containsAll(['run', 'App']));
  });

  test('shell functions and comment sections', () {
    const code = '''
#!/usr/bin/env bash
# 安装依赖
install() {
  echo hi
}
''';
    final symbols = extractCodeOutline(code, 'bash');
    expect(symbols.map((s) => s.name), containsAll(['安装依赖', 'install']));
    expect(symbols.last.kind, 'function');
  });

  test('unknown language yields no outline', () {
    expect(extractCodeOutline('anything', 'plaintext'), isEmpty);
  });

  test('caps symbol count', () {
    final code = List.generate(600, (i) => 'fn f$i() {}').join('\n');
    expect(extractCodeOutline(code, 'rust'), hasLength(maxCodeSymbols));
  });
}
