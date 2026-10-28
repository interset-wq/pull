import 'package:flutter_test/flutter_test.dart';
import 'package:reader/src/local/mirror_state.dart';

void main() {
  group('MirrorManifest 增量判定', () {
    test('未见过的文件需要拷贝', () {
      final m = MirrorManifest.empty();
      expect(m.needsCopy('a.md', 10, 1000), isTrue);
    });

    test('快照一致时不重复拷贝，任一维度变化都要拷贝', () {
      final m = MirrorManifest.empty()
        ..record('a.md', 10, 1000);
      expect(m.needsCopy('a.md', 10, 1000), isFalse);
      expect(m.needsCopy('a.md', 11, 1000), isTrue);
      expect(m.needsCopy('a.md', 10, 1001), isTrue);
    });

    test('stalePaths 只返回源侧已消失的条目', () {
      final m = MirrorManifest.empty()
        ..record('keep.md', 1, 1)
        ..record('gone.md', 2, 2);
      expect(m.stalePaths({'keep.md', 'new.md'}), ['gone.md']);
    });

    test('encode/decode 往返保持快照', () {
      final m = MirrorManifest.empty()
        ..record('目录/中文 名.md', 42, 1712345678000);
      final back = MirrorManifest.decode(m.encode());
      expect(back.length, 1);
      expect(back.stampOf('目录/中文 名.md'), const MirrorStamp(42, 1712345678000));
      expect(back.needsCopy('目录/中文 名.md', 42, 1712345678000), isFalse);
    });

    test('损坏或半截 JSON 退化为空清单而不是抛异常', () {
      expect(MirrorManifest.decode('{"files": {"a.md"').isEmpty, isTrue);
      expect(MirrorManifest.decode('null').isEmpty, isTrue);
      expect(MirrorManifest.decode('[1,2,3]').isEmpty, isTrue);
      // 单条记录字段缺失时只丢这条，其余保留
      final partial = MirrorManifest.decode(
        '{"files": {"ok.md": {"s": 1, "m": 2}, "bad.md": {"s": "x"}}}',
      );
      expect(partial.contains('ok.md'), isTrue);
      expect(partial.contains('bad.md'), isFalse);
    });
  });

  group('PendingEdits 待写回集合', () {
    test('去重、可移除、冲突标记可往返', () {
      final p = PendingEdits.empty()
        ..put(const PendingEdit(
          relativePath: 'notes/a.md',
          base: MirrorStamp(10, 100),
        ))
        ..put(const PendingEdit(
          relativePath: 'notes/a.md',
          base: MirrorStamp(11, 200),
        ));
      expect(p.length, 1);
      expect(p['notes/a.md']!.base, const MirrorStamp(11, 200));

      p.markConflict('notes/a.md');
      expect(p['notes/a.md']!.conflict, isTrue);

      final back = PendingEdits.decode(p.encode());
      expect(back.length, 1);
      expect(back['notes/a.md']!.conflict, isTrue);
      expect(back['notes/a.md']!.base, const MirrorStamp(11, 200));

      p.remove('notes/a.md');
      expect(p.isEmpty, isTrue);
    });

    test('无 base 的记录（老版本/未知来源）也能解析', () {
      final back = PendingEdits.decode('{"files": [{"p": "x.md"}]}');
      expect(back['x.md']!.base, isNull);
      expect(back['x.md']!.conflict, isFalse);
    });

    test('损坏数据退化为空集合', () {
      expect(PendingEdits.decode('{').isEmpty, isTrue);
      expect(PendingEdits.decode('{"files": "nope"}').isEmpty, isTrue);
    });
  });
}
