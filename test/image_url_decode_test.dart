import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader/src/ui/repo_image.dart';

/// 回归：markdown 包按 CommonMark 对链接目的地址做百分号编码，中文
/// 文件名图片（如 ../figures/介绍下joyrl演示.png）渲染失败。
/// 解码 + 本地解析必须还原到磁盘上的原始文件名。
void main() {
  group('markdown 图片链接解码与本地解析', () {
    test('编码的中文文件名还原为原始名', () {
      const raw = '介绍下joyrl演示.png';
      final encoded = Uri.encodeFull(raw);
      expect(encoded.contains('%'), isTrue);
      expect(decodeMarkdownUrl(encoded), raw);
    });

    test('普通路径原样返回', () {
      expect(decodeMarkdownUrl('img/photo.png'), 'img/photo.png');
    });

    test('相对路径中文图片解析为存在的文件', () {
      final base = Directory('temp/img-resolve-test');
      if (base.existsSync()) base.deleteSync(recursive: true);
      final docs = Directory(
          '${base.path}${Platform.pathSeparator}docs')
        ..createSync(recursive: true);
      final c6 =
          Directory('${docs.path}${Platform.pathSeparator}C6')..createSync();
      final figures =
          Directory('${docs.path}${Platform.pathSeparator}figures')
            ..createSync();
      final img = File('${figures.path}${Platform.pathSeparator}介绍下joyrl演示.png')
        ..createSync();

      final resolved = resolveRepoFile(
        decodeMarkdownUrl(
            Uri.encodeFull('../figures/介绍下joyrl演示.png')),
        c6.path,
      );
      expect(resolved.existsSync(), isTrue);
      // 解析路径与磁盘路径指向同一文件（分隔符风格统一比较）
      expect(
        resolved.path.replaceAll('\\', '/'),
        img.path.replaceAll('\\', '/'),
      );

      base.deleteSync(recursive: true);
    });
  });
}
