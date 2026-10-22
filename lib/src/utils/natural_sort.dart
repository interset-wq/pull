/// 自然排序：按正则提取的数字串以数值比较，
/// `chapter10` 排在 `chapter2` 之后（纯字典序会把 10 排在 2 前）。
int compareNatural(String a, String b) {
  final pattern = RegExp(r'(\d+)|(\D+)');
  final ma = pattern.allMatches(a).iterator;
  final mb = pattern.allMatches(b).iterator;
  while (true) {
    final ha = ma.moveNext() ? ma.current : null;
    final hb = mb.moveNext() ? mb.current : null;
    if (ha == null && hb == null) return 0;
    if (ha == null) return -1;
    if (hb == null) return 1;
    final da = ha.group(1);
    final db = hb.group(1);
    if (da != null && db != null) {
      final cmp = int.parse(da).compareTo(int.parse(db));
      if (cmp != 0) return cmp;
      // 数值相同但写法不同（"02" vs "2"）时保持确定顺序
      if (da.length != db.length) return da.length.compareTo(db.length);
    } else {
      final sa = (da ?? ha.group(2))!.toLowerCase();
      final sb = (db ?? hb.group(2))!.toLowerCase();
      final cmp = sa.compareTo(sb);
      if (cmp != 0) return cmp;
    }
  }
}

/// 按文件名的自然顺序比较（提取文件名后比较，忽略扩展名差异干扰）。
int compareNaturalByName(String pathA, String pathB) {
  final a = pathA.split('/').last.toLowerCase();
  final b = pathB.split('/').last.toLowerCase();
  return compareNatural(a, b);
}
