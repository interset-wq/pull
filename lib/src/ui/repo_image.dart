import 'dart:io';

import 'package:flutter/material.dart';

/// 统一图片加载：相对路径解析为仓库本地文件，网络图片直接加载，
/// 失败统一展示占位。
Widget buildRepoImage(
  String url, {
  required String repoRoot,
  BoxFit fit = BoxFit.contain,
}) {
  final clean = url.trim();
  if (clean.startsWith('http://') || clean.startsWith('https://')) {
    return Image.network(
      clean,
      fit: fit,
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
  final file = File(
    '$repoRoot${Platform.pathSeparator}'
    '${clean.replaceAll('/', Platform.pathSeparator)}',
  );
  if (!file.existsSync()) return const _ImageErrorBox();
  return Image.file(
    file,
    fit: fit,
    errorBuilder: (_, _, _) => const _ImageErrorBox(),
  );
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
