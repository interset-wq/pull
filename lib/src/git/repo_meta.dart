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

  /// 一条最近阅读记录（全局）。
  const RepoMeta.recent({required this.lastOpened, this.url, this.branch});

  /// 进度/收藏/历史条目数量上限，防止 meta 文件无限膨胀。
  static const _maxEntries = 50;

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

  /// 读取文章的已保存滚动进度（0~1 的比例位置），无记录返回 null。
  static double? readProgress(String repoRoot, String relativePath) {
    final map = _readRaw(repoRoot)['progress'];
    if (map is! Map<String, dynamic>) return null;
    final v = map[relativePath.replaceAll('\\', '/')];
    if (v is! num) return null;
    return v.clamp(0.0, 1.0).toDouble();
  }

  /// 保存文章滚动进度（0~1 比例，跨设备/字号变化可恢复）。
  static void saveProgress(
    String repoRoot,
    String relativePath,
    double fraction,
  ) {
    final raw = _readRaw(repoRoot);
    final map = (raw['progress'] as Map<String, dynamic>?) ?? {};
    map[relativePath.replaceAll('\\', '/')] = fraction;
    raw['progress'] = map;
    _write(repoRoot, raw);
  }

  /// 文章是否已收藏。
  static bool isStarred(String repoRoot, String relativePath) {
    final list = _readRaw(repoRoot)['starred'];
    return list is List &&
        list.contains(relativePath.replaceAll('\\', '/'));
  }

  /// 切换收藏状态，返回切换后的状态。
  static bool toggleStar(String repoRoot, String relativePath) {
    final raw = _readRaw(repoRoot);
    final key = relativePath.replaceAll('\\', '/');
    final list = ((raw['starred'] as List?) ?? []).cast<String>().toList();
    if (!list.remove(key)) list.insert(0, key);
    raw['starred'] = list;
    _write(repoRoot, raw);
    return list.contains(key);
  }

  /// 全仓库收藏列表（按收藏先后，新的在前）。
  static List<String> starredFiles(String repoRoot) =>
      ((read(repoRoot) == null ? null : _readRaw(repoRoot)['starred'])
              as List?)
          ?.cast<String>()
          .toList() ??
      const [];

  /// 记录一次阅读到全局最近阅读（去重、新的在前、限量）。
  /// 每条格式 `仓库名<TAB>相对路径`，跨仓库聚合展示。
  static void pushRecent(String repoRoot, String relativePath) {
    final name = repoRoot.split(Platform.pathSeparator).last;
    final entry = '$name\t${relativePath.replaceAll('\\', '/')}';
    final f = _recentsFile(repoRoot);
    final raw = _readJson(f);
    final list = (raw['recents'] as List?)?.cast<String>().toList() ?? [];
    list
      ..remove(entry)
      ..insert(0, entry);
    if (list.length > _maxEntries) {
      list.removeRange(_maxEntries, list.length);
    }
    raw['recents'] = list;
    _writeJson(f, raw);
  }

  /// 全局最近阅读列表，新的在前，每条为 (仓库名, 相对路径)。
  static List<(String, String)> readRecents(String reposRoot) =>
      ((_readJson(_recentsFile(reposRoot))['recents'] as List?) ?? const [])
          .cast<String>()
          .map((e) {
        final i = e.indexOf('\t');
        return i < 0 ? null : (e.substring(0, i), e.substring(i + 1));
      })
          .whereType<(String, String)>()
          .toList();

  static Map<String, dynamic> _readJson(File f) {
    if (!f.existsSync()) return <String, dynamic>{};
    try {
      final d = jsonDecode(f.readAsStringSync());
      return d is Map<String, dynamic> ? d : <String, dynamic>{};
    } on Object {
      return <String, dynamic>{};
    }
  }

  static void _writeJson(File f, Map<String, dynamic> raw) {
    try {
      f.parent.createSync(recursive: true);
      f.writeAsStringSync(jsonEncode(raw));
    } on Object {
      // 元数据仅用于展示，写失败不影响功能
    }
  }

  /// 全局最近阅读文件：`<reposRoot>/.meta/recents.json`。
  /// repoRoot 可传仓库目录（取其父级）或 repos 根目录本身。
  static File _recentsFile(String repoOrReposRoot) {
    final p = repoOrReposRoot;
    final reposRoot =
        Directory('$p${Platform.pathSeparator}.git').existsSync()
            ? Directory(p).parent.path
            : p;
    return File(
      '$reposRoot${Platform.pathSeparator}.meta'
      '${Platform.pathSeparator}recents.json',
    );
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
