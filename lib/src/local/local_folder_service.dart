import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:path_provider/path_provider.dart';
import 'package:saf/saf.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../notes/note_scanner.dart';
import '../git/repo_meta.dart';

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
class LocalFolderService {
  static const _foldersKey = 'localFolders';
  static const markerName = '.pullread_local';

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
      final picked = await Saf().pickDirectory(writePermission: false);
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
    } on Object {
      // 镜像清理失败无碍
    }
    await _saveFolders(
      (await listFolders())
          .where((x) => x.uri != folder.uri)
          .toList(),
    );
  }

  /// 重建镜像：全量重拷（个人笔记目录体量小，正确性优先）。
  /// 只镜像应用可读的文件类型（md/ipynb/代码/图片），返回文件数。
  static Future<int> syncFolder(LocalFolder folder) =>
      Platform.isAndroid ? _syncSaf(folder) : _syncFromPath(folder);

  static Future<int> _syncSaf(LocalFolder folder) async {
    final target = await mirrorDir(folder.name);
    if (target.existsSync()) target.deleteSync(recursive: true);
    target.createSync(recursive: true);
    final saf = Saf();
    var count = 0;
    await for (final e in saf.walk(folder.uri)) {
      if (e.file.isDir) continue;
      if (!_isMirrorable(_ext(e.relativePath))) continue;
      // 超大文件（>32MB）视为非笔记资产，跳过
      if (e.file.length > 32 * 1024 * 1024) continue;
      final bytes = await saf.readFileBytes(e.file.uri);
      await _writeMirror(
        target,
        e.relativePath.replaceAll('/', Platform.pathSeparator),
        bytes,
      );
      count++;
    }
    File(
      '${target.path}${Platform.pathSeparator}$markerName',
    ).writeAsStringSync('1');
    return count;
  }

  static Future<int> _syncFromPath(LocalFolder folder) async {
    final target = await mirrorDir(folder.name);
    if (target.existsSync()) target.deleteSync(recursive: true);
    target.createSync(recursive: true);
    final src = Directory(folder.uri);
    if (!src.existsSync()) return 0;
    var count = 0;
    await for (final e in src.list(recursive: true, followLinks: false)) {
      if (e is! File) continue;
      final rel = e.path.substring(src.path.length + 1);
      if (!_isMirrorable(_ext(rel))) continue;
      if (e.statSync().size > 32 * 1024 * 1024) continue;
      await _writeMirror(target, rel, await e.readAsBytes());
      count++;
    }
    File(
      '${target.path}${Platform.pathSeparator}$markerName',
    ).writeAsStringSync('1');
    return count;
  }

  static Future<void> _writeMirror(
    Directory target,
    String relative,
    List<int> bytes,
  ) async {
    final out = File(
      '${target.path}${Platform.pathSeparator}$relative',
    );
    await out.create(recursive: true);
    await out.writeAsBytes(bytes, flush: true);
  }

  static String _ext(String path) {
    final base = path.split(Platform.pathSeparator).last;
    final dot = base.lastIndexOf('.');
    return dot > 0 ? base.substring(dot).toLowerCase() : '';
  }

  static bool _isMirrorable(String ext) =>
      NoteScanner.mdExtensions.contains(ext) ||
      NoteScanner.codeExtensions.contains(ext) ||
      NoteScanner.imageExtensions.contains(ext);
}
