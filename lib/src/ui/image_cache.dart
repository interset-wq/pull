import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path_provider/path_provider.dart';

/// 一个缓存文件的元信息（纯数据，便于单测淘汰策略）。
class CacheFileInfo {
  const CacheFileInfo({
    required this.path,
    required this.size,
    required this.modifiedMs,
  });

  final String path;
  final int size;
  final int modifiedMs;
}

/// 远程图片磁盘缓存（离线阅读用）：按 URL 哈希落盘，
/// 目录 `<docs>/imgcache`，总量超过 [maxBytes] 时按「最后写入时间」
/// 淘汰最旧的（近似 LRU——写入时间即最近一次刷新时间）。
///
/// 读写失败一律静默：缓存只是锦上添花，不能影响正文渲染。
class ImageDiskCache {
  static const _dirName = 'imgcache';

  /// 缓存总量上限：200MB（约几百张截图，对手机可接受）。
  static const maxBytes = 200 * 1024 * 1024;

  /// 累计写入超过这个量才触发一次淘汰扫描，避免每张图都遍历目录。
  static const _trimEvery = 32 * 1024 * 1024;

  /// 超过这个年龄的缓存会在后台悄悄刷新一次（徽章类图片不必每次进文重下）。
  static const staleAfter = Duration(days: 7);

  static Directory? _dir;
  static int _writtenSinceTrim = 0;

  static Future<Directory> _ensureDir() async {
    final cached = _dir;
    if (cached != null && cached.existsSync()) return cached;
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}${Platform.pathSeparator}$_dirName');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return _dir = dir;
  }

  /// 读取缓存；没有或损坏返回 null。
  static Future<Uint8List?> read(String url) async {
    try {
      final file = await _fileFor(url);
      if (!file.existsSync()) return null;
      return await file.readAsBytes();
    } on Object {
      return null;
    }
  }

  /// 写入缓存（覆盖旧版本）。
  static Future<void> store(String url, List<int> bytes) async {
    try {
      final file = await _fileFor(url);
      await file.writeAsBytes(bytes, flush: true);
      _writtenSinceTrim += bytes.length;
      if (_writtenSinceTrim >= _trimEvery) {
        _writtenSinceTrim = 0;
        await _trim();
      }
    } on Object {
      // 缓存写失败不影响本次显示
    }
  }

  /// 缓存是否已过期到需要后台刷新（不存在也返回 false——调用方走网络）。
  static Future<bool> isStale(String url) async {
    try {
      final file = await _fileFor(url);
      if (!file.existsSync()) return false;
      final age = DateTime.now().difference(file.statSync().modified);
      return age > staleAfter;
    } on Object {
      return false;
    }
  }

  /// 删除单条缓存（解码失败时让下次重新下载）。
  static Future<void> remove(String url) async {
    try {
      final file = await _fileFor(url);
      if (file.existsSync()) file.deleteSync();
    } on Object {
      // 忽略
    }
  }

  static Future<File> _fileFor(String url) async {
    final dir = await _ensureDir();
    return File('${dir.path}${Platform.pathSeparator}${keyFor(url)}');
  }

  static Future<void> _trim() async {
    try {
      final dir = await _ensureDir();
      final files = dir.listSync().whereType<File>();
      final infos = <CacheFileInfo>[];
      for (final f in files) {
        final stat = f.statSync();
        infos.add(
          CacheFileInfo(
            path: f.path,
            size: stat.size,
            modifiedMs: stat.modified.millisecondsSinceEpoch,
          ),
        );
      }
      for (final path in planEvictions(infos)) {
        try {
          File(path).deleteSync();
        } on Object {
          // 忽略
        }
      }
    } on Object {
      // 忽略
    }
  }

  /// 淘汰计划：总量不超过 [maxBytes] 时为空；否则从最旧开始删到上限内。
  /// 纯函数，便于单测。
  @visibleForTesting
  static List<String> planEvictions(
    List<CacheFileInfo> files, {
    int maxBytes = maxBytes,
  }) {
    var total = 0;
    for (final f in files) {
      total += f.size;
    }
    if (total <= maxBytes) return const [];
    final sorted = [...files]..sort((a, b) => a.modifiedMs.compareTo(b.modifiedMs));
    final out = <String>[];
    for (final f in sorted) {
      if (total <= maxBytes) break;
      out.add(f.path);
      total -= f.size;
    }
    return out;
  }

  /// URL → 文件名：两个 32 位哈希拼成 64 位，避免 32 位碰撞导致图片串图。
  /// 稳定（同一 URL 永远同一文件名），不依赖运行时 hash 随机化。
  @visibleForTesting
  static String keyFor(String url) {
    var h1 = 0x811c9dc5;
    var h2 = 5381;
    for (final byte in utf8.encode(url)) {
      h1 = ((h1 ^ byte) * 0x01000193) & 0xFFFFFFFF;
      h2 = ((h2 * 33) + byte) & 0xFFFFFFFF;
    }
    return '${h1.toRadixString(16).padLeft(8, '0')}'
        '${h2.toRadixString(16).padLeft(8, '0')}.img';
  }
}
