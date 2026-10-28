import 'dart:io';
import 'dart:isolate';

/// 目录体积统计：递归累加常规文件字节数（含隐藏文件）。
/// 目录可能很大（整仓克隆），遍历放后台 isolate，UI 只等结果。
Future<int> dirSizeInBackground(String path) {
  if (path.isEmpty) return Future.value(0);
  return Isolate.run(() => _sizeOf(Directory(path)));
}

int _sizeOf(Directory dir) {
  var total = 0;
  try {
    if (!dir.existsSync()) return 0;
    for (final e in dir.listSync(recursive: true, followLinks: false)) {
      try {
        if (e is File) total += e.lengthSync();
      } on Object {
        // 单个文件取不到大小（权限/竞态删除）不影响总量
      }
    }
  } on Object {
    // 目录不存在或不可读：按 0 处理
  }
  return total;
}

/// 字节数 → 人类可读：B / KB / MB / GB，一位小数，整 KB 以下不显示小数。
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kb = bytes / 1024;
  if (kb < 1024) return '${_trim(kb)} KB';
  final mb = kb / 1024;
  if (mb < 1024) return '${_trim(mb)} MB';
  return '${_trim(mb / 1024)} GB';
}

String _trim(double v) =>
    v >= 100 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
