import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:http/http.dart' as http;

/// 统一图片加载：相对路径基于 [baseDir]（markdown 文件所在目录）解析，
/// 支持 ./ 与 ../ 相对层级；网络图片直接加载（SVG 自动识别渲染），
/// 失败统一展示占位。
Widget buildRepoImage(
  String url, {
  required String baseDir,
  BoxFit fit = BoxFit.contain,
}) {
  final clean = url.trim();
  if (clean.startsWith('http://') || clean.startsWith('https://')) {
    return _NetworkImage(url: clean, fit: fit);
  }
  return Image.file(
    _resolveLocal(clean, baseDir),
    fit: fit,
    errorBuilder: (_, _, _) => const _ImageErrorBox(),
  );
}

/// 网络图片：先取字节再按内容渲染——图床（shields.io、contrib.rocks、
/// star-history 等）普遍返回 SVG，Image.network 无法解码，需走 flutter_svg。
class _NetworkImage extends StatefulWidget {
  const _NetworkImage({required this.url, required this.fit});

  final String url;
  final BoxFit fit;

  @override
  State<_NetworkImage> createState() => _NetworkImageState();
}

class _NetworkImageState extends State<_NetworkImage> {
  late final Future<Uint8List?> _bytes = _fetch();

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

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: _bytes,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox(
            width: 120,
            height: 120,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        final bytes = snapshot.data;
        if (bytes == null) return const _ImageErrorBox();
        if (_looksLikeSvg(bytes)) {
          return SvgPicture.memory(bytes, fit: widget.fit);
        }
        return Image.memory(bytes, fit: widget.fit);
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
  const _ImageErrorBox();

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
      child: Icon(
        Icons.broken_image_outlined,
        size: 32,
        color: theme.colorScheme.outline,
      ),
    );
  }
}
