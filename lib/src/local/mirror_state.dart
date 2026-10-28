/// 本地文件夹镜像的状态记录（纯逻辑，不碰文件系统，便于单测）。
///
/// 镜像根下维护两份记录：
/// - 清单：每个已镜像文件的源侧快照 `(size, mtimeMs)`，用于增量同步——
///   只有快照不匹配才重读源文件字节。
/// - 待写回：编辑器保存但尚未成功写回原文件夹的文件。这些文件在
///   重镜像时必须跳过，否则镜像里的修改会被源侧旧内容覆盖（丢数据）。
library;

import 'dart:convert';

/// 一个文件的源侧快照：大小 + 修改时间（毫秒）。
///
/// 只比 (size, mtime) 是刻意的取舍：读源文件内容来比对指纹在 SAF 上
/// 等于全量读一遍，增量同步就失去意义。同一毫秒内改动且大小不变的
/// 极端情况会漏判，对笔记阅读场景可接受。
class MirrorStamp {
  const MirrorStamp(this.size, this.mtimeMs);

  final int size;
  final int mtimeMs;

  bool matches(int size, int mtimeMs) =>
      this.size == size && this.mtimeMs == mtimeMs;

  Map<String, Object> toJson() => {'s': size, 'm': mtimeMs};

  static MirrorStamp? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final size = raw['s'];
    final mtime = raw['m'];
    if (size is! num || mtime is! num) return null;
    return MirrorStamp(size.toInt(), mtime.toInt());
  }

  @override
  bool operator ==(Object other) =>
      other is MirrorStamp && other.size == size && other.mtimeMs == mtimeMs;

  @override
  int get hashCode => Object.hash(size, mtimeMs);

  @override
  String toString() => 'MirrorStamp($size, $mtimeMs)';
}

/// 镜像清单：相对路径 → 源侧快照。
class MirrorManifest {
  MirrorManifest._(this._files);

  factory MirrorManifest.empty() => MirrorManifest._({});

  /// 从 JSON 文本恢复；损坏/半截数据一律视为空清单（下次全量补一遍，
  /// 最坏只是多拷几个文件，不会丢内容）。
  static MirrorManifest decode(String? text) {
    if (text == null || text.trim().isEmpty) return MirrorManifest.empty();
    try {
      final raw = jsonDecode(text);
      if (raw is! Map) return MirrorManifest.empty();
      final files = raw['files'];
      if (files is! Map) return MirrorManifest.empty();
      final out = <String, MirrorStamp>{};
      files.forEach((key, value) {
        if (key is! String) return;
        final stamp = MirrorStamp.fromJson(value);
        if (stamp != null) out[key] = stamp;
      });
      return MirrorManifest._(out);
    } on Object {
      return MirrorManifest.empty();
    }
  }

  final Map<String, MirrorStamp> _files;

  Map<String, MirrorStamp> get files => Map.unmodifiable(_files);

  bool get isEmpty => _files.isEmpty;

  int get length => _files.length;

  bool contains(String relativePath) => _files.containsKey(relativePath);

  MirrorStamp? stampOf(String relativePath) => _files[relativePath];

  /// 源文件是否需要（重新）写入镜像：未见过的、或快照不匹配的。
  bool needsCopy(String relativePath, int size, int mtimeMs) {
    final stamp = _files[relativePath];
    return stamp == null || !stamp.matches(size, mtimeMs);
  }

  void record(String relativePath, int size, int mtimeMs) {
    _files[relativePath] = MirrorStamp(size, mtimeMs);
  }

  void remove(String relativePath) => _files.remove(relativePath);

  /// 清单里有、但本次源目录扫描没见到的路径——源侧已删除，
  /// 镜像里对应文件也应删除（待写回的除外，由调用方过滤）。
  List<String> stalePaths(Set<String> present) =>
      _files.keys.where((k) => !present.contains(k)).toList();

  String encode() => jsonEncode({
        'version': 1,
        'files': {
          for (final entry in _files.entries) entry.key: entry.value.toJson(),
        },
      });
}

/// 一条待写回记录：编辑器里保存过、但写回原文件夹失败的镜像文件。
class PendingEdit {
  const PendingEdit({
    required this.relativePath,
    this.base,
    this.conflict = false,
  });

  /// 相对镜像根的路径（统一用 `/`）。
  final String relativePath;

  /// 上次从源侧镜像时的快照；用于判断「未写回期间源文件是否被外部改动」。
  final MirrorStamp? base;

  /// 源文件在此期间被外部改动过：直接写回会覆盖别人的更新，
  /// 需要用户显式确认（设置页「以镜像为准覆盖」）。
  final bool conflict;

  PendingEdit copyWith({MirrorStamp? base, bool? conflict}) => PendingEdit(
        relativePath: relativePath,
        base: base ?? this.base,
        conflict: conflict ?? this.conflict,
      );

  Map<String, Object> toJson() => {
        'p': relativePath,
        if (base != null) 'b': base!.toJson(),
        if (conflict) 'c': true,
      };

  static PendingEdit? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final path = raw['p'];
    if (path is! String || path.isEmpty) return null;
    return PendingEdit(
      relativePath: path,
      base: MirrorStamp.fromJson(raw['b']),
      conflict: raw['c'] == true,
    );
  }
}

/// 待写回文件集合（按相对路径去重）。
class PendingEdits {
  PendingEdits._(this._items);

  factory PendingEdits.empty() => PendingEdits._({});

  static PendingEdits decode(String? text) {
    if (text == null || text.trim().isEmpty) return PendingEdits.empty();
    try {
      final raw = jsonDecode(text);
      final list = raw is Map ? raw['files'] : raw;
      if (list is! List) return PendingEdits.empty();
      final out = <String, PendingEdit>{};
      for (final item in list) {
        final edit = PendingEdit.fromJson(item);
        if (edit != null) out[edit.relativePath] = edit;
      }
      return PendingEdits._(out);
    } on Object {
      return PendingEdits.empty();
    }
  }

  final Map<String, PendingEdit> _items;

  List<PendingEdit> get items => List.unmodifiable(_items.values);

  int get length => _items.length;

  bool get isEmpty => _items.isEmpty;

  bool contains(String relativePath) => _items.containsKey(relativePath);

  PendingEdit? operator [](String relativePath) => _items[relativePath];

  void put(PendingEdit edit) => _items[edit.relativePath] = edit;

  void remove(String relativePath) => _items.remove(relativePath);

  void markConflict(String relativePath) {
    final edit = _items[relativePath];
    if (edit != null) _items[relativePath] = edit.copyWith(conflict: true);
  }

  String encode() => jsonEncode({
        'version': 1,
        'files': [for (final edit in _items.values) edit.toJson()],
      });
}
