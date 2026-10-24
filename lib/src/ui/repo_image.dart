import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:http/http.dart' as http;

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
      _resolveLocal(clean, baseDir),
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
  late Future<Uint8List?> _bytes = _fetch();

  Future<Uint8List?> _fetch() async {
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

  void _retry() => setState(() => _bytes = _fetch());

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
          return SvgPicture.memory(bytes, fit: widget.fit);
        }
        return Image.memory(
          bytes,
          fit: widget.fit,
          frameBuilder: _fadeIn,
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

/// 相对路径基于 baseDir 解析；绝对路径原样使用；归一化 ./ 与 ../。
File _resolveLocal(String src, String baseDir) {
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
  return hasDrive ? joined : '/$joined';
}

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
