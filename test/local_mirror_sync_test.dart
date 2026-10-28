import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader/src/local/local_folder_service.dart';

/// 本地文件夹镜像的回归测试（桌面路径实现，可跑在 Windows/Linux CI）。
///
/// 重点不是「拷贝对不对」，而是两条不变量：
/// 1. 编辑器保存过但写回失败的文件，重镜像时不能被源侧旧内容覆盖；
/// 2. 源侧删除的文件，镜像里也要删除。
void main() {
  late Directory root;
  late Directory src;
  late Directory mirror;
  late LocalFolder folder;

  setUp(() {
    root = Directory(
      'temp/mirror-sync-${DateTime.now().microsecondsSinceEpoch}',
    )..createSync(recursive: true);
    src = Directory('${root.path}/src')..createSync(recursive: true);
    mirror = Directory('${root.path}/mirror')..createSync(recursive: true);
    folder = LocalFolder(uri: src.path, name: 'mirror');
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  test('首次镜像全量拷贝，未变化的文件不重复拷贝', () async {
    File('${src.path}/a.md').writeAsStringSync('v1');
    Directory('${src.path}/sub').createSync();
    File('${src.path}/sub/b.md').writeAsStringSync('b');

    expect(await LocalFolderService.syncInto(folder, mirror), 2);
    expect(File('${mirror.path}/a.md').readAsStringSync(), 'v1');
    expect(File('${mirror.path}/sub/b.md').readAsStringSync(), 'b');

    // 第二次没有任何源侧变化：0 次写入
    expect(await LocalFolderService.syncInto(folder, mirror), 0);
  });

  test('源文件变化时只重拷变化的那一个', () async {
    File('${src.path}/a.md').writeAsStringSync('v1');
    File('${src.path}/b.md').writeAsStringSync('b');
    await LocalFolderService.syncInto(folder, mirror);

    File('${src.path}/a.md').writeAsStringSync('v2 changed');
    expect(await LocalFolderService.syncInto(folder, mirror), 1);
    expect(File('${mirror.path}/a.md').readAsStringSync(), 'v2 changed');
  });

  test('待写回的编辑在重镜像时不被源侧旧内容覆盖', () async {
    File('${src.path}/a.md').writeAsStringSync('v1');
    await LocalFolderService.syncInto(folder, mirror);

    // 模拟编辑器保存：先落镜像，写回原文件夹失败 → 记录待写回
    File('${mirror.path}/a.md').writeAsStringSync('edited in app');
    LocalFolderService.markPending(mirror.path, 'a.md');
    expect(LocalFolderService.pendingCount(mirror.path), 1);

    // 源侧此时仍是旧内容（写回失败），再次打开会触发一次同步
    File('${src.path}/a.md').writeAsStringSync('v1');
    await LocalFolderService.syncInto(folder, mirror);

    expect(
      File('${mirror.path}/a.md').readAsStringSync(),
      'edited in app',
      reason: '未写回的修改是唯一副本，不能被覆盖',
    );
    expect(LocalFolderService.pendingCount(mirror.path), 1);
  });

  test('源侧删除的文件从镜像移除，待写回的不删', () async {
    File('${src.path}/keep.md').writeAsStringSync('keep');
    File('${src.path}/drop.md').writeAsStringSync('drop');
    File('${src.path}/pending.md').writeAsStringSync('old');
    await LocalFolderService.syncInto(folder, mirror);

    File('${mirror.path}/pending.md').writeAsStringSync('edited');
    LocalFolderService.markPending(mirror.path, 'pending.md');

    File('${src.path}/drop.md').deleteSync();
    File('${src.path}/pending.md').deleteSync();

    await LocalFolderService.syncInto(folder, mirror);

    expect(File('${mirror.path}/drop.md').existsSync(), isFalse);
    expect(File('${mirror.path}/keep.md').existsSync(), isTrue);
    expect(
      File('${mirror.path}/pending.md').readAsStringSync(),
      'edited',
      reason: '源侧删除不应连带删掉未写回的编辑',
    );
  });

  test('写回成功清除记录后，同步恢复正常覆盖', () async {
    File('${src.path}/a.md').writeAsStringSync('v1');
    await LocalFolderService.syncInto(folder, mirror);

    File('${mirror.path}/a.md').writeAsStringSync('edited');
    LocalFolderService.markPending(mirror.path, 'a.md');
    LocalFolderService.clearPending(mirror.path, 'a.md');
    expect(LocalFolderService.pendingCount(mirror.path), 0);

    File('${src.path}/a.md').writeAsStringSync('v2 from pc');
    await LocalFolderService.syncInto(folder, mirror);
    expect(File('${mirror.path}/a.md').readAsStringSync(), 'v2 from pc');
  });
}
