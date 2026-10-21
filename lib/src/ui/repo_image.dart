import 'dart:io';

import 'package:flutter/material.dart';

/// 统一图片加载：相对路径基于 [baseDir]（markdown 文件所在目录）解析，
/// 支持 ./ 与 ../ 相对层级；网络图片直接加载，失败统一展示占位。
Widget buildRepoImage(
  String url, {
  required String baseDir,
  BoxFit fit = BoxFit.contain,
}) {
  final clean = url.trim();
  if (clean.startsWith('http://') || clean.startsWith('https://')) {
    return Image.network(
      clean,
      fit: fit,
      headers: const {'User-Agent': 'Mozilla/5.0'},
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return const SizedBox(
          width: 120,
          height: 120,
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        );
      },
      errorBuilder: (_, _, _) => const _ImageErrorBox(),
    );
  }
  return Image.file(
    _resolveLocal(clean, baseDir),
    fit: fit,
    errorBuilder: (_, _, _) => const _ImageErrorBox(),
  );
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
