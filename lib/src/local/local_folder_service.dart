import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path_provider/path_provider.dart';
import 'package:saf/saf.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../notes/note_index.dart';
import '../notes/note_scanner.dart';
import '../git/repo_meta.dart';
import 'mirror_state.dart';

/// 一条本地文件夹记录（Roadmap「本地文件阅读器」）。
/// [uri] 在 Android 上是 SAF tree URI（content://…，授权一次持久化），
/// 在桌面端是用户选中的目录绝对路径。
class LocalFolder {
  const LocalFolder({required this.uri, required this.name});

  final String uri;
  final String name;

  /// 持久化编码 `uri||name`（URI 不含 `||`，可安全切分）。
  static LocalFolder decode(String s) {
    final i = s.indexOf('||');
    return LocalFolder(uri: s.substring(0, i), name: s.substring(i + 2));
  }

  String encode() => '$uri||$name';
}

/// 本地文件夹服务：系统选择器授权 → 镜像到应用私有目录 → 与 git 仓库
/// 同构地用 RepoPage/MarkdownViewerPage 浏览阅读（渲染、进度、收藏、
/// 导出全部复用，无需为 SAF 单独抽象内容源）。
/// Android 走 SAF（授权目录无真实路径，dart:io 读不到）；桌面走
/// file_selector。镜像标记 `.pullread_local` 用于 RepoPage 识别本地来源。
///
/// 镜像同步是增量的（[MirrorManifest] 记录每个文件的源侧快照），并且
/// 保护「编辑器已保存、但写回原文件夹失败」的文件（[PendingEdits]）：
/// 这些文件的镜像版本在源侧修好之前绝不覆盖——早期实现每次打开都整目录
/// 重建镜像，会把没写回的修改静默冲掉。
class LocalFolderService {
  static const _foldersKey = 'localFolders';
  static const markerName = '.pullread_local';
  static const manifestName = '.pullread_manifest.json';
  static const pendingName = '.pullread_pending.json';

  /// 超大文件（>32MB）视为非笔记资产，不镜像。
  static const maxMirrorBytes = 32 * 1024 * 1024;

  static Future<List<LocalFolder>> listFolders() async {
    try {
      final sp = await SharedPreferences.getInstance();
      return (sp.getStringList(_foldersKey) ?? const <String>[])
          .map(LocalFolder.decode)
          .toList();
    } on Object {
      return const [];
    }
  }

  static Future<void> _saveFolders(List<LocalFolder> folders) async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setStringList(
        _foldersKey,
        folders.map((f) => f.encode()).toList(),
      );
    } on Object {
      // 保存失败不影响本次会话
    }
  }

  /// 镜像根目录 `<docs>/local`：与 repos 根并列，互不混入。
  static Future<Directory> mirrorDir(String name) async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(
      '${docs.path}${Platform.pathSeparator}local'
      '${Platform.pathSeparator}$name',
    );
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  static bool isLocalMirror(String repoPath) =>
      File('$repoPath${Platform.pathSeparator}$markerName').existsSync();

  /// 找到镜像路径对应的本地文件夹记录（RepoPage 刷新镜像用）。
  static Future<LocalFolder?> matchMirror(String mirrorPath) async {
    for (final f in await listFolders()) {
      if ((await mirrorDir(f.name)).path == mirrorPath) return f;
    }
    return null;
  }

  /// 授权新文件夹并完成首次镜像；用户取消返回 null。
  /// 文件夹名与已有记录重名时自动追加序号（镜像目录按名隔离）。
  ///
  /// 必须申请**写**权限：编辑器保存要写回原文件夹，只给读权限的话
  /// 每次保存都只能落在镜像里（见 [PendingEdits]）。
  static Future<LocalFolder?> addFolder() async {
    final pickedName = await _pick();
    if (pickedName == null) return null;
    final taken = (await listFolders()).map((f) => f.name).toSet();
    var name = pickedName.name;
    var i = 2;
    while (taken.contains(name)) {
      name = '${pickedName.name}-$i';
      i++;
    }
    final folder = LocalFolder(uri: pickedName.uri, name: name);
    await syncFolder(folder);
    await _saveFolders([...await listFolders(), folder]);
    return folder;
  }

  static Future<LocalFolder?> _pick() async {
    if (Platform.isAndroid) {
      final picked = await Saf().pickDirectory(writePermission: true);
      if (picked == null) return null;
      return LocalFolder(uri: picked.uri, name: picked.name);
    }
    // 桌面（Windows 预览）：选真实目录，镜像走 dart:io
    final path = await getDirectoryPath();
    if (path == null) return null;
    return LocalFolder(
      uri: path,
      name: path.split(Platform.pathSeparator).last,
    );
  }

  /// 移除授权与镜像（原文件夹不受影响）。
  static Future<void> removeFolder(LocalFolder folder) async {
    try {
      if (Platform.isAndroid) {
        await Saf().releasePersistedPermission(folder.uri);
      }
    } on Object {
      // 权限已失效也无碍
    }
    try {
      final mirror = await mirrorDir(folder.name);
      if (mirror.existsSync()) mirror.deleteSync(recursive: true);
      RepoMeta.remove(mirror.path);
      NoteIndexCache.remove(mirror.path);
    } on Object {
      // 镜像清理失败无碍
    }
    await _saveFolders(
      (await listFolders())
          .where((x) => x.uri != folder.uri)
          .toList(),
    );
  }

  /// 增量重建镜像（只重读源侧变化的文件），返回本次实际写入的文件数。
  ///
  /// 先尽力重试上次没写回的修改：写回成功后源侧即最新，增量同步不会
  /// 覆盖镜像里用户的编辑。
  static Future<int> syncFolder(LocalFolder folder) async {
    await retryPending(folder);
    final target = await mirrorDir(folder.name);
    return syncInto(folder, target);
  }

  /// 把 [folder] 的源文件增量同步到 [target]，返回本次实际写入的文件数。
  /// 单独暴露镜像目录是为了让测试能直接指定临时目录（不经过 path_provider）。
  @visibleForTesting
  static Future<int> syncInto(LocalFolder folder, Directory target) =>
      Platform.isAndroid ? _syncSaf(folder, target) : _syncFromPath(folder, target);

  static Future<int> _syncSaf(LocalFolder folder, Directory target) async {
    final manifest = _readManifest(target);
    final pending = _readPending(target);
    final saf = Saf();
    final seen = <String>{};
    var copied = 0;
    await for (final entry in saf.walk(folder.uri)) {
      final file = entry.file;
      if (file.isDir) continue;
      final rel = _key(entry.relativePath);
      if (!_isMirrorable(_ext(rel))) continue;
      if (file.length > maxMirrorBytes) continue;
      seen.add(rel);
      // 未写回的编辑：保留镜像版本，绝不用源侧旧内容覆盖
      if (pending.contains(rel)) continue;
      final mirrored = File(_abs(target, rel));
      if (mirrored.existsSync() &&
          !manifest.needsCopy(rel, file.length, file.lastModified)) {
        continue;
      }
      final bytes = await saf.readFileBytes(file.uri);
      await _writeMirror(target, rel, bytes);
      manifest.record(rel, file.length, file.lastModified);
      copied++;
    }
    final pruned = _prune(target, manifest, pending, seen);
    _writeManifest(target, manifest);
    _writePending(target, pending);
    if (pruned) _pruneEmptyDirs(target);
    _writeMarker(target);
    return copied;
  }

  static Future<int> _syncFromPath(LocalFolder folder, Directory target) async {
    final manifest = _readManifest(target);
    final pending = _readPending(target);
    final src = Directory(folder.uri);
    final seen = <String>{};
    var copied = 0;
    if (src.existsSync()) {
      await for (final e in src.list(recursive: true, followLinks: false)) {
        if (e is! File) continue;
        final rel = _key(
          e.path.substring(src.path.length + 1),
        );
        if (!_isMirrorable(_ext(rel))) continue;
        final stat = e.statSync();
        if (stat.size > maxMirrorBytes) continue;
        seen.add(rel);
        if (pending.contains(rel)) continue;
        final mirrored = File(_abs(target, rel));
        if (mirrored.existsSync() &&
            !manifest.needsCopy(rel, stat.size, stat.modified.millisecondsSinceEpoch)) {
          continue;
        }
        await _writeMirror(target, rel, await e.readAsBytes());
        manifest.record(rel, stat.size, stat.modified.millisecondsSinceEpoch);
        copied++;
      }
    }
    // 源目录整体不可读（授权失效/被移动）时不要清空镜像：保留旧内容，
    // 用户至少还能读，重新授权后再同步
    final pruned = src.existsSync()
        ? _prune(target, manifest, pending, seen)
        : false;
    _writeManifest(target, manifest);
    _writePending(target, pending);
    if (pruned) _pruneEmptyDirs(target);
    _writeMarker(target);
    return copied;
  }

  /// 删除源侧已不存在的镜像文件（待写回的保留），并清理指向已消失
  /// 镜像文件的待写回记录。返回是否发生了删除。
  static bool _prune(
    Directory target,
    MirrorManifest manifest,
    PendingEdits pending,
    Set<String> seen,
  ) {
    var removed = false;
    for (final rel in manifest.stalePaths(seen)) {
      if (pending.contains(rel)) continue;
      try {
        final f = File(_abs(target, rel));
        if (f.existsSync()) {
          f.deleteSync();
          removed = true;
        }
      } on Object {
        // 删除失败（占用/权限）无碍，下次再试
      }
      manifest.remove(rel);
    }
    for (final edit in pending.items.toList()) {
      if (!File(_abs(target, edit.relativePath)).existsSync()) {
        pending.remove(edit.relativePath);
      }
    }
    return removed;
  }

  /// 源文件被删后可能留下空目录，顺手清掉（不影响仍有内容的目录）。
  static void _pruneEmptyDirs(Directory root) {
    try {
      final dirs = root
          .listSync(recursive: true, followLinks: false)
          .whereType<Directory>()
          .toList()
        ..sort(
          (a, b) => _depth(b.path).compareTo(_depth(a.path)),
        );
      for (final d in dirs) {
        try {
          if (d.listSync(followLinks: false).isEmpty) d.deleteSync();
        } on Object {
          // 忽略
        }
      }
    } on Object {
      // 忽略
    }
  }

  static int _depth(String path) =>
      path.split(Platform.pathSeparator).length;

  // ---- 待写回（编辑器保存失败） ---------------------------------------

  /// 记录一个写回失败的镜像文件（编辑器保存时调用）。
  ///
  /// [base] 取清单里该文件上次镜像时的源侧快照：下次重试时据此判断
  /// 源文件是否在未写回期间被外部改动（改动过就是冲突，不能盲覆盖）。
  static void markPending(String mirrorPath, String relativePath) {
    final target = Directory(mirrorPath);
    final rel = _key(relativePath);
    final manifest = _readManifest(target);
    final pending = _readPending(target);
    pending.put(PendingEdit(relativePath: rel, base: manifest.stampOf(rel)));
    _writePending(target, pending);
  }

  /// 写回成功后清除记录（编辑器保存成功时调用）。
  static void clearPending(String mirrorPath, String relativePath) {
    final target = Directory(mirrorPath);
    final rel = _key(relativePath);
    final pending = _readPending(target);
    if (!pending.contains(rel)) return;
    pending.remove(rel);
    _writePending(target, pending);
    final manifest = _readManifest(target);
    manifest.remove(rel);
    _writeManifest(target, manifest);
  }

  /// 重试写回所有待写回文件，返回 (成功数, 失败数)。
  ///
  /// [force] 为 true 时忽略冲突检查，直接用镜像内容覆盖源文件。
  static Future<(int, int)> retryPending(
    LocalFolder folder, {
    bool force = false,
  }) async {
    final target = await mirrorDir(folder.name);
    final pending = _readPending(target);
    if (pending.isEmpty) return (0, 0);
    final manifest = _readManifest(target);
    var ok = 0;
    var failed = 0;
    for (final edit in pending.items.toList()) {
      final mirrorFile = File(_abs(target, edit.relativePath));
      if (!mirrorFile.existsSync()) {
        pending.remove(edit.relativePath);
        continue;
      }
      final source = await _sourceStamp(folder, edit.relativePath);
      final base = edit.base ?? manifest.stampOf(edit.relativePath);
      // 源文件消失了（在电脑上删除）视作「未改动」：把修改写回去，
      // 宁可多恢复一个文件，也不静默丢掉用户刚写的内容
      final untouched = source == null || base == null || source == base;
      if (!untouched && !force) {
        pending.markConflict(edit.relativePath);
        failed++;
        continue;
      }
      final written = await writeBack(
        folder,
        edit.relativePath,
        mirrorFile.readAsBytesSync(),
      );
      if (written) {
        pending.remove(edit.relativePath);
        manifest.remove(edit.relativePath);
        ok++;
      } else {
        failed++;
      }
    }
    _writePending(target, pending);
    _writeManifest(target, manifest);
    return (ok, failed);
  }

  /// 当前镜像的待写回文件数（首页/设置页展示用）。
  static int pendingCount(String mirrorPath) =>
      _readPending(Directory(mirrorPath)).length;

  /// 当前镜像的待写回明细。
  static List<PendingEdit> pendingEdits(String mirrorPath) =>
      _readPending(Directory(mirrorPath)).items;

  /// 所有本地文件夹的待写回明细（设置页汇总）。
  static Future<List<(LocalFolder, PendingEdit)>> allPending() async {
    final out = <(LocalFolder, PendingEdit)>[];
    for (final folder in await listFolders()) {
      final dir = await mirrorDir(folder.name);
      for (final edit in _readPending(dir).items) {
        out.add((folder, edit));
      }
    }
    return out;
  }

  static Future<MirrorStamp?> _sourceStamp(
    LocalFolder folder,
    String relativePath,
  ) async {
    final segments = relativePath.split('/');
    if (Platform.isAndroid) {
      try {
        final doc = await Saf().child(folder.uri, segments);
        if (doc == null || doc.isDir) return null;
        return MirrorStamp(doc.length, doc.lastModified);
      } on Object {
        return null;
      }
    }
    final file = File(
      '${folder.uri}${Platform.pathSeparator}'
      '${segments.join(Platform.pathSeparator)}',
    );
    if (!file.existsSync()) return null;
    final stat = file.statSync();
    return MirrorStamp(stat.size, stat.modified.millisecondsSinceEpoch);
  }

  /// 把镜像内容写回用户授权的原文件夹（编辑器保存与待写回重试共用）。
  static Future<bool> writeBack(
    LocalFolder folder,
    String relativePath,
    List<int> bytes,
  ) async {
    final segments = relativePath.split('/');
    final name = segments.removeLast();
    if (Platform.isAndroid) {
      try {
        var dirUri = folder.uri;
        for (final seg in segments) {
          final d = await Saf().child(dirUri, [seg]);
          if (d == null || !d.isDir) return false;
          dirUri = d.uri;
        }
        await Saf().writeFileBytes(
          dirUri,
          name,
          _mimeOf(name),
          Uint8List.fromList(bytes),
          overwrite: true,
        );
        return true;
      } on Object {
        return false;
      }
    }
    try {
      final parentPath = segments.isEmpty
          ? folder.uri
          : '${folder.uri}${Platform.pathSeparator}'
              '${segments.join(Platform.pathSeparator)}';
      // 不替用户在源侧重建目录结构：父目录没了就报失败，留给人工处理
      final parent = Directory(parentPath);
      if (!parent.existsSync()) return false;
      final target = File('$parentPath${Platform.pathSeparator}$name');
      await target.writeAsBytes(bytes, flush: true);
      return true;
    } on Object {
      return false;
    }
  }

  static String _mimeOf(String name) {
    final ext = _ext(name);
    return switch (ext) {
      '.md' || '.markdown' || '.mdx' => 'text/markdown',
      '.txt' || '.log' => 'text/plain',
      '.json' => 'application/json',
      _ => 'application/octet-stream',
    };
  }

  // ---- 镜像文件写入与状态文件 ----------------------------------------

  static Future<void> _writeMirror(
    Directory target,
    String relative,
    List<int> bytes,
  ) async {
    final out = File(_abs(target, relative));
    await out.create(recursive: true);
    await out.writeAsBytes(bytes, flush: true);
  }

  static void _writeMarker(Directory target) {
    try {
      File('${target.path}${Platform.pathSeparator}$markerName')
          .writeAsStringSync('1');
    } on Object {
      // 标记写失败只会让 RepoPage 当普通目录处理，不影响阅读
    }
  }

  static File _stateFile(Directory mirror, String name) =>
      File('${mirror.path}${Platform.pathSeparator}$name');

  static String _readState(File file) {
    try {
      return file.existsSync() ? file.readAsStringSync() : '';
    } on Object {
      return '';
    }
  }

  static void _writeState(File file, String text) {
    try {
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(text);
    } on Object {
      // 状态文件损坏最坏只是多做一次全量镜像，不丢内容
    }
  }

  static MirrorManifest _readManifest(Directory mirror) =>
      MirrorManifest.decode(_readState(_stateFile(mirror, manifestName)));

  static void _writeManifest(Directory mirror, MirrorManifest manifest) =>
      _writeState(_stateFile(mirror, manifestName), manifest.encode());

  static PendingEdits _readPending(Directory mirror) =>
      PendingEdits.decode(_readState(_stateFile(mirror, pendingName)));

  static void _writePending(Directory mirror, PendingEdits pending) =>
      _writeState(_stateFile(mirror, pendingName), pending.encode());

  /// 清单/待写回里的相对路径统一用 `/`；落盘时再转平台分隔符。
  static String _key(String path) => path.replaceAll('\\', '/');

  static String _abs(Directory root, String relative) =>
      '${root.path}${Platform.pathSeparator}'
      '${relative.replaceAll('/', Platform.pathSeparator)}';

  static String _ext(String path) {
    final base = path.split(RegExp(r'[/\\]')).last;
    final dot = base.lastIndexOf('.');
    return dot > 0 ? base.substring(dot).toLowerCase() : '';
  }

  static bool _isMirrorable(String ext) =>
      NoteScanner.mdExtensions.contains(ext) ||
      NoteScanner.codeExtensions.contains(ext) ||
      NoteScanner.imageExtensions.contains(ext);
}
