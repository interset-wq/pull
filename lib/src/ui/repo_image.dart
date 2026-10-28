import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:http/http.dart' as http;

import 'image_cache.dart';

/// 统一图片加载：相对路径基于 [baseDir]（markdown 文件所在目录）解析，
/// 支持 ./ 与 ../ 相对层级；网络图片直接加载（SVG 自动识别渲染），
/// 失败统一展示占位（网络图支持点击重试）。
///
/// [backdrop] 为图片垫一层浅色背景：透明 PNG/SVG 图表多按白底设计，
/// 深色主题下直接渲染会不可读；图库（黑底沉浸浏览）不开启。
Widget buildRepoImage(
  String url, {
  required String baseDir,
  BoxFit fit = BoxFit.contain,
  bool backdrop = false,
}) {
  final clean = url.trim();
  final Widget child;
  if (clean.startsWith('http://') || clean.startsWith('https://')) {
    child = _NetworkImage(url: clean, fit: fit);
  } else {
    child = Image.file(
      resolveRepoFile(decodeMarkdownUrl(clean), baseDir),
      fit: fit,
      frameBuilder: _fadeIn,
      errorBuilder: (_, _, _) => const _ImageErrorBox(),
    );
  }
  if (!backdrop) return child;
  return Container(color: _backdropColor, child: child);
}

/// 图表白底垫色：比纯白柔和，浅色主题下与页面融为一体。
const Color _backdropColor = Color(0xFFF7F7F8);

/// 图片加载完成后渐入，避免解码完成的瞬间生硬闪现。
Widget _fadeIn(
  BuildContext context,
  Widget child,
  int? frame, [
  bool wasSynchronouslyLoaded = false,
]) {
  if (wasSynchronouslyLoaded) return child;
  return AnimatedOpacity(
    opacity: frame == null ? 0 : 1,
    duration: const Duration(milliseconds: 220),
    child: child,
  );
}

/// 网络图片：先取字节再按内容渲染——图床（shields.io、contrib.rocks、
/// star-history 等）普遍返回 SVG，Image.network 无法解码，需走 flutter_svg。
/// 加载中显示全宽占位；失败显示可重试的错误块。
class _NetworkImage extends StatefulWidget {
  const _NetworkImage({required this.url, required this.fit});

  final String url;
  final BoxFit fit;

  @override
  State<_NetworkImage> createState() => _NetworkImageState();
}

class _NetworkImageState extends State<_NetworkImage> {
  late Future<Uint8List?> _bytes = _load();

  /// 先看磁盘缓存：离线/弱网时已读过的图片立刻出图，不再等 30 秒超时。
  /// 缓存超过 7 天会在后台悄悄刷新一次，本次仍用旧图（不阻塞渲染）。
  Future<Uint8List?> _load() async {
    final cached = await ImageDiskCache.read(widget.url);
    if (cached != null) {
      if (await ImageDiskCache.isStale(widget.url)) {
        unawaited(_refreshInBackground());
      }
      return cached;
    }
    final fresh = await _download();
    if (fresh != null) await ImageDiskCache.store(widget.url, fresh);
    return fresh;
  }

  Future<Uint8List?> _download() async {
    try {
      final res = await http
          .get(
            Uri.parse(widget.url),
            headers: const {'User-Agent': 'Mozilla/5.0'},
          )
          .timeout(const Duration(seconds: 30));
      return res.statusCode == 200 ? res.bodyBytes : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _refreshInBackground() async {
    final fresh = await _download();
    if (fresh != null) await ImageDiskCache.store(widget.url, fresh);
  }

  /// 手动重试：丢弃可能损坏的缓存，直接重新下载。
  void _retry() {
    setState(() {
      _bytes = () async {
        await ImageDiskCache.remove(widget.url);
        final fresh = await _download();
        if (fresh != null) await ImageDiskCache.store(widget.url, fresh);
        return fresh;
      }();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: _bytes,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          // 全宽占位：与最终图片占位面积接近，减少加载完成时的跳动
          return Container(
            width: double.infinity,
            height: 180,
            alignment: Alignment.center,
            color: _backdropColor,
            child: const CircularProgressIndicator(strokeWidth: 2),
          );
        }
        final bytes = snapshot.data;
        if (bytes == null) return _ImageErrorBox(onRetry: _retry);
        if (_looksLikeSvg(bytes)) {
          return SvgPicture.memory(
            bytes,
            fit: widget.fit,
            errorBuilder: (_, _, _) => _ImageErrorBox(onRetry: _retry),
          );
        }
        return Image.memory(
          bytes,
          fit: widget.fit,
          frameBuilder: _fadeIn,
          errorBuilder: (_, _, _) => _ImageErrorBox(onRetry: _retry),
        );
      },
    );
  }
}

/// 按内容嗅探 SVG（部分图床 content-type 不规范，直接看字节更可靠）。
bool _looksLikeSvg(Uint8List bytes) {
  final head = String.fromCharCodes(bytes.take(512)).toLowerCase();
  return head.contains('<svg') || head.contains('<?xml');
}

/// markdown 包按 CommonMark 规范对链接目的地址做百分号编码（中文文件名
/// 变成 %E4%BB.. 之类），而本地文件按原始名存储，解析前必须还原。
/// 已是普通路径（不含 %）原样返回；含字面 % 的非法编码解码失败也原样返回。
String decodeMarkdownUrl(String src) {
  if (!src.contains('%')) return src;
  try {
    return Uri.decodeFull(src);
  } catch (_) {
    return src;
  }
}

/// 相对路径基于 baseDir 解析；绝对路径原样使用；归一化 ./ 与 ../。
File resolveRepoFile(String src, String baseDir) {
  final isAbsolute =
      src.startsWith('/') || RegExp(r'^[A-Za-z]:[\\/]').hasMatch(src);
  final joined = isAbsolute
      ? src
      : '$baseDir${Platform.pathSeparator}'
          '${src.replaceAll('/', Platform.pathSeparator)}';
  return File(_normalize(joined));
}

String _normalize(String path) {
  final hasDrive = RegExp(r'^[A-Za-z]:').hasMatch(path);
  // 以 / 开头的路径（Windows 上指当前盘符根）保留前导斜杠；
  // 纯相对路径不能凭空加 /，否则会错误地指到盘符根目录。
  final isRooted = path.startsWith('/') || path.startsWith('\\');
  final out = <String>[];
  for (final part in path.replaceAll('\\', '/').split('/')) {
    if (part.isEmpty || part == '.') continue;
    if (part == '..') {
      if (out.isNotEmpty && !out.last.endsWith(':')) out.removeLast();
      continue;
    }
    out.add(part);
  }
  final joined = out.join('/');
  if (!isRooted) return _toNative(joined);
  return hasDrive ? _toNative(joined) : '/${_toNative(joined)}';
}

/// Windows 上统一为反斜杠，与 File/Directory 返回的路径风格一致，
/// 便于调用方做路径相等比较；POSIX 原样。
String _toNative(String path) =>
    Platform.isWindows ? path.replaceAll('/', '\\') : path;

class _ImageErrorBox extends StatelessWidget {
  const _ImageErrorBox({this.onRetry});

  /// 非 null 时显示「点击重试」（网络图）；本地文件缺失则只展示占位。
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      height: 120,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withAlpha(80),
        borderRadius: BorderRadius.circular(8),
      ),
      child: onRetry == null
          ? Icon(
              Icons.broken_image_outlined,
              size: 32,
              color: theme.colorScheme.outline,
            )
          : InkWell(
              onTap: onRetry,
              borderRadius: BorderRadius.circular(8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.broken_image_outlined,
                    size: 28,
                    color: theme.colorScheme.outline,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '加载失败，点击重试',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
