import 'dart:convert';
import 'dart:io';

import 'sync_service.dart' show RepoChange;

/// 一条段落级书签：记住文章里的某个位置（标题 + 全篇滚动比例）。
///
/// 比例而不是像素偏移：字号/屏宽变化后仍能落回附近；标题索引让列表能显示
/// 「在哪一章」，也方便后续按章节聚合。
class Bookmark {
  const Bookmark({
    required this.relativePath,
    required this.fraction,
    required this.title,
    required this.createdAt,
    this.headingIndex,
  });

  final String relativePath;

  /// 全篇滚动比例（0~1），与阅读进度同一套坐标系。
  final double fraction;

  /// 书签所在章节的标题（无标题文档用文件名）。
  final String title;

  /// 章节在 TOC 里的下标；无标题文档为 null。
  final int? headingIndex;

  final DateTime createdAt;

  Map<String, Object?> toJson() => {
        'p': relativePath,
        'f': fraction,
        't': title,
        'ts': createdAt.toIso8601String(),
        if (headingIndex != null) 'h': headingIndex,
      };

  static Bookmark? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final path = raw['p'];
    final fraction = raw['f'];
    final title = raw['t'];
    final ts = raw['ts'];
    if (path is! String || path.isEmpty || fraction is! num) return null;
    return Bookmark(
      relativePath: path.replaceAll('\\', '/'),
      fraction: fraction.clamp(0.0, 1.0).toDouble(),
      title: title is String && title.isNotEmpty ? title : path.split('/').last,
      createdAt: DateTime.tryParse(ts is String ? ts : '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      headingIndex: raw['h'] is int ? raw['h'] as int : null,
    );
  }
}

/// 仓库元数据（纯本地展示用）：克隆来源、分支、最近打开的文件。
/// 存于 `<reposRoot>/.meta/<仓库名>.json` —— 刻意放在克隆仓库之外，
/// 不污染只读仓库内容，pull 也不会触碰它。
class RepoMeta {
  const RepoMeta({
    this.url,
    this.branch,
    this.lastOpened,
    this.syncedAt,
  });

  final String? url;
  final String? branch;
  final String? lastOpened;

  /// 最近一次成功同步（克隆或 pull）的时间；用于仓库卡展示。
  final DateTime? syncedAt;

  /// 一条最近阅读记录（全局）。
  const RepoMeta.recent({
    required this.lastOpened,
    this.url,
    this.branch,
    this.syncedAt,
  });

  /// 进度/收藏/历史条目数量上限，防止 meta 文件无限膨胀。
  static const _maxEntries = 50;

  /// 最近更新标记的条目上限（超过整体清空）。
  static const _maxRecentChanges = 200;

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
      syncedAt: DateTime.tryParse((raw['syncedAt'] as String?) ?? ''),
    );
  }

  /// 仓库置顶（Roadmap「仓库管理·仓库置顶」）：存于本仓库 meta，
  /// 随 RepoMeta.remove 与仓库一并消失，无需单独清理。
  static bool isPinned(String repoRoot) => _readRaw(repoRoot)['pinned'] == true;

  /// 切换置顶状态，返回切换后的值。
  static bool togglePin(String repoRoot) {
    final raw = _readRaw(repoRoot);
    final v = !(raw['pinned'] == true);
    raw['pinned'] = v;
    _write(repoRoot, raw);
    return v;
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

  /// 记录一次成功同步（pull 之后调用，克隆时已由 writeClone 写入）。
  static void touchSynced(String repoRoot) {
    final raw = _readRaw(repoRoot);
    raw['syncedAt'] = DateTime.now().toIso8601String();
    _write(repoRoot, raw);
  }

  /// 记录 pull 带来的文件变更（「更新后的阅读感知」打标数据）。
  /// 覆盖同名条目；超过 [_maxRecentChanges] 条时整体清空——打标只是
  /// 提示，不是账本，与其算淘汰不如提示"这轮更新很多"。
  static void setRecentChanges(
    String repoRoot,
    Iterable<RepoChange> changes,
  ) {
    final raw = _readRaw(repoRoot);
    final map = <String, String>{
      if (raw['recentChanges'] is Map)
        for (final e in (raw['recentChanges'] as Map).entries)
          if (e.key is String && e.value is String) e.key as String: e.value as String,
    };
    for (final c in changes) {
      map[c.path] = c.added ? 'a' : 'm';
    }
    if (map.length > _maxRecentChanges) {
      map.clear();
    }
    raw['recentChanges'] = map;
    _write(repoRoot, raw);
  }

  /// 未读的更新标记：相对路径（`/` 分隔）→ 'a' 新增 / 'm' 修改。
  static Map<String, String> readRecentChanges(String repoRoot) {
    final raw = _readRaw(repoRoot)['recentChanges'];
    if (raw is! Map) return const {};
    return {
      for (final e in raw.entries)
        if (e.key is String && e.value is String) e.key as String: e.value as String,
    };
  }

  /// 打开/阅读某文件后清除它的更新标记。
  static void clearRecentChange(String repoRoot, String relativePath) {
    final raw = _readRaw(repoRoot);
    final map = raw['recentChanges'];
    if (map is! Map || map.remove(relativePath) == null) return;
    raw['recentChanges'] = map;
    _write(repoRoot, raw);
  }

  /// 一次清空本仓库的全部更新标记（更新收件箱的「全部已读」）。
  static void clearRecentChanges(String repoRoot) {
    final raw = _readRaw(repoRoot);
    if (raw.remove('recentChanges') == null) return;
    _write(repoRoot, raw);
  }

  /// 单仓库书签上限：超出丢弃最旧的。
  static const _maxBookmarks = 100;

  /// 读取本仓库书签，最新的在前；损坏条目跳过。
  static List<Bookmark> readBookmarks(String repoRoot) {
    final raw = _readRaw(repoRoot)['bookmarks'];
    if (raw is! List) return const [];
    final out = [
      for (final item in raw) ?Bookmark.fromJson(item),
    ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return out;
  }

  /// 添加书签：同一文件 1% 以内的位置视为同一条（更新时间与标题），
  /// 超过上限丢弃最旧的。
  static void addBookmark(String repoRoot, Bookmark bookmark) {
    final raw = _readRaw(repoRoot);
    final list = [
      for (final item in (raw['bookmarks'] as List?) ?? const [])
        ?Bookmark.fromJson(item),
    ];
    const epsilon = 0.01;
    list.removeWhere((b) =>
        b.relativePath == bookmark.relativePath &&
        (b.fraction - bookmark.fraction).abs() < epsilon);
    list.insert(0, bookmark);
    if (list.length > _maxBookmarks) {
      list.removeRange(_maxBookmarks, list.length);
    }
    raw['bookmarks'] = [for (final b in list) b.toJson()];
    _write(repoRoot, raw);
  }

  /// 删除一条书签（按文件 + 创建时间定位）。
  static void removeBookmark(String repoRoot, Bookmark bookmark) {
    final raw = _readRaw(repoRoot);
    final rawList = raw['bookmarks'];
    if (rawList is! List) return;
    final list = [
      for (final item in rawList) ?Bookmark.fromJson(item),
    ];
    final before = list.length;
    list.removeWhere((b) =>
        b.relativePath == bookmark.relativePath &&
        b.createdAt == bookmark.createdAt);
    if (list.length == before) return;
    raw['bookmarks'] = [for (final b in list) b.toJson()];
    _write(repoRoot, raw);
  }

  /// 读取文章的已保存进度，返回 (比例 0~1, 最近标题索引)。
  /// 兼容旧数据：只存了比例（num）时标题索引为 null。
  static (double, int?) readProgressInfo(
    String repoRoot,
    String relativePath,
  ) {
    final map = _readRaw(repoRoot)['progress'];
    if (map is! Map<String, dynamic>) return (0.0, null);
    final v = map[relativePath.replaceAll('\\', '/')];
    if (v is num) return (v.clamp(0.0, 1.0).toDouble(), null);
    if (v is Map<String, dynamic>) {
      final f = (v['f'] as num?)?.clamp(0.0, 1.0).toDouble() ?? 0.0;
      final h = v['h'] is int ? v['h'] as int : null;
      return (f, h);
    }
    return (0.0, null);
  }

  /// 保存文章进度：比例（兜底）+ 最近标题索引（恢复时按段落锚点
  /// 定位，比纯比例更准——字号/窗口变化导致的布局高度漂移不影响
  /// 标题的位置）。
  static void saveProgressInfo(
    String repoRoot,
    String relativePath,
    double fraction,
    int? headingIndex,
  ) {
    final raw = _readRaw(repoRoot);
    final map = (raw['progress'] as Map<String, dynamic>? ) ?? {};
    map[relativePath.replaceAll('\\', '/')] = {
      'f': fraction,
      if (headingIndex != null && headingIndex >= 0) 'h': headingIndex,
    };
    raw['progress'] = map;
    _write(repoRoot, raw);
  }

  /// 读取文章的已保存滚动进度（0~1 的比例位置），无记录返回 null。
  static double? readProgress(String repoRoot, String relativePath) {
    final (f, _) = readProgressInfo(repoRoot, relativePath);
    return f > 0 ? f : null;
  }

  /// 全部有阅读记录的文件：相对路径 → 0~1。仓库页用它展示阅读状态。
  static Map<String, double> readAllProgress(String repoRoot) {
    final map = _readRaw(repoRoot)['progress'];
    if (map is! Map) return const {};
    final out = <String, double>{};
    for (final entry in map.entries) {
      final key = entry.key;
      if (key is! String) continue;
      final value = entry.value;
      if (value is num) {
        out[key.replaceAll('\\', '/')] =
            value.clamp(0.0, 1.0).toDouble();
      } else if (value is Map && value['f'] is num) {
        out[key.replaceAll('\\', '/')] =
            (value['f'] as num).clamp(0.0, 1.0).toDouble();
      }
    }
    return out;
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
  static void pushRecent(
    String repoRoot,
    String relativePath, {
    int limit = 5,
  }) {
    final name = repoRoot.split(Platform.pathSeparator).last;
    final entry = '$name\t${relativePath.replaceAll('\\', '/')}';
    final f = _recentsFile(repoRoot);
    final raw = _readJson(f);
    final list = (raw['recents'] as List?)?.cast<String>().toList() ?? [];
    list
      ..remove(entry)
      ..insert(0, entry);
    final cap = limit.clamp(1, _maxEntries);
    if (list.length > cap) {
      list.removeRange(cap, list.length);
    }
    raw['recents'] = list;
    _writeJson(f, raw);
  }

  /// 清空全局最近阅读。
  static void clearRecents(String reposRoot) {
    final f = _recentsFile(reposRoot);
    if (f.existsSync()) {
      try {
        f.deleteSync();
      } on Object {
        // 忽略
      }
    }
  }

  /// 清空所有仓库的收藏。
  static void clearAllStars(String reposRoot) {
    final root = Directory(reposRoot);
    if (!root.existsSync()) return;
    for (final d in root.listSync(followLinks: false)) {
      if (d is! Directory) continue;
      if (!Directory('${d.path}${Platform.pathSeparator}.git').existsSync()) {
        continue;
      }
      final raw = _readRaw(d.path);
      if (!raw.containsKey('starred')) continue;
      raw['starred'] = <String>[];
      _write(d.path, raw);
    }
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
