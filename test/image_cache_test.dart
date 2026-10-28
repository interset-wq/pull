import 'package:flutter_test/flutter_test.dart';
import 'package:reader/src/ui/image_cache.dart';

void main() {
  group('ImageDiskCache.keyFor', () {
    test('同一 URL 始终得到同一文件名', () {
      const url = 'https://example.com/a/b.png?x=1';
      expect(ImageDiskCache.keyFor(url), ImageDiskCache.keyFor(url));
      expect(ImageDiskCache.keyFor(url).endsWith('.img'), isTrue);
    });

    test('不同 URL 得到不同文件名（大小写也算不同资源）', () {
      expect(
        ImageDiskCache.keyFor('https://a/b.png'),
        isNot(ImageDiskCache.keyFor('https://a/B.png')),
      );
      expect(
        ImageDiskCache.keyFor('https://a/b.png'),
        isNot(ImageDiskCache.keyFor('https://a/c.png')),
      );
    });

    test('中文与超长 URL 可用', () {
      final key = ImageDiskCache.keyFor(
        'https://example.com/图/${'x' * 500}.png',
      );
      expect(key.length, 20); // 16 位十六进制 + '.img'
    });
  });

  group('ImageDiskCache.planEvictions', () {
    CacheFileInfo file(String path, int size, int modified) =>
        CacheFileInfo(path: path, size: size, modifiedMs: modified);

    test('总量未超上限时不淘汰', () {
      final plan = ImageDiskCache.planEvictions(
        [file('a', 60, 1), file('b', 30, 2)],
        maxBytes: 100,
      );
      expect(plan, isEmpty);
    });

    test('超上限时从最旧的开始删，删到上限内即停', () {
      final plan = ImageDiskCache.planEvictions(
        [
          file('old', 50, 1),
          file('mid', 50, 2),
          file('new', 50, 3),
        ],
        maxBytes: 120,
      );
      // 150 > 120：删最旧 1 个后 100 ≤ 120
      expect(plan, ['old']);
    });

    test('单个大文件超上限时也删（避免永远占满）', () {
      final plan = ImageDiskCache.planEvictions(
        [file('huge', 500, 1)],
        maxBytes: 100,
      );
      expect(plan, ['huge']);
    });

    test('多个旧文件需要连续删除', () {
      final plan = ImageDiskCache.planEvictions(
        [
          file('a', 100, 1),
          file('b', 100, 2),
          file('c', 100, 3),
        ],
        maxBytes: 100,
      );
      expect(plan, ['a', 'b']);
    });
  });
}
