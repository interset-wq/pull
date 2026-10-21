import 'dart:convert';
import 'dart:io';

/// 仓库元数据（纯本地展示用）：克隆来源、分支、最近打开的文件。
/// 存于 `<reposRoot>/.meta/<仓库名>.json` —— 刻意放在克隆仓库之外，
/// 不污染只读仓库内容，pull 也不会触碰它。
class RepoMeta {
  const RepoMeta({this.url, this.branch, this.lastOpened});

  final String? url;
  final String? branch;
  final String? lastOpened;

  static File _file(String repoRoot) {
    final name = repoRoot.split(Platform.pathSeparator).last;
    final reposRoot = Directory(repoRoot).parent.path;
    return File(
      '$reposRoot${Platform.pathSeparator}.meta'
      '${Platform.pathSeparator}$name.json',
    );
  }

  /// 卡片展示的远端来源：host + /owner/repo。
  String get source {
    final u = url;
    if (u == null || u.isEmpty) return '';
    try {
      final uri = Uri.parse(u);
      final path = uri.path.replaceFirst(RegExp(r'\.git$'), '');
      return uri.host.isEmpty
          ? path.replaceAll(RegExp(r'^/'), '')
          : '${uri.host}$path';
    } on Object {
      return u;
    }
  }

  static Map<String, dynamic> _readRaw(String repoRoot) {
    final f = _file(repoRoot);
    if (!f.existsSync()) return <String, dynamic>{};
    try {
      final d = jsonDecode(f.readAsStringSync());
      return d is Map<String, dynamic> ? d : <String, dynamic>{};
    } on Object {
      return <String, dynamic>{};
    }
  }

  static void _write(String repoRoot, Map<String, dynamic> raw) {
    try {
      final f = _file(repoRoot);
      f.parent.createSync(recursive: true);
      f.writeAsStringSync(jsonEncode(raw));
    } on Object {
      // 元数据仅用于展示，写失败不影响功能
    }
  }

  static RepoMeta? read(String repoRoot) {
    final raw = _readRaw(repoRoot);
    if (raw.isEmpty) return null;
    return RepoMeta(
      url: raw['url'] as String?,
      branch: raw['branch'] as String?,
      lastOpened: raw['lastOpened'] as String?,
    );
  }

  static void writeClone(
    String repoRoot, {
    required String url,
    String branch = 'main',
  }) {
    final raw = _readRaw(repoRoot);
    raw['url'] = url;
    raw['branch'] = branch;
    raw['syncedAt'] = DateTime.now().toIso8601String();
    _write(repoRoot, raw);
  }

  static void touchLastOpened(String repoRoot, String relativePath) {
    final raw = _readRaw(repoRoot);
    raw['lastOpened'] = relativePath;
    _write(repoRoot, raw);
  }

  static void remove(String repoRoot) {
    try {
      final f = _file(repoRoot);
      if (f.existsSync()) f.deleteSync();
    } on Object {
      // 忽略
    }
  }
}
