import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// 阅读统计（Roadmap「检索与标注·阅读统计」）：纯本地，按天累计阅读时长
/// 与阅读文章数。存于 `<reposRoot>/.meta/stats.json`，与仓库元数据同目录，
/// 不污染只读仓库内容。
///
/// 结构：{"days": {"2026-10-26": {"minutes": 12.5, "articles": ["repo/file"]}}}
/// 只保留最近 [_keepDays] 天；读写失败静默（统计是辅助功能）。
class ReadingStats {
  const ReadingStats._();

  static const _keepDays = 30;

  /// 单日单篇文章只记一次篇数；时长按会话实际累计（调用方负责裁剪）。
  static void record(String repoRoot, String relativePath, double minutes) {
    if (minutes <= 0) return;
    try {
      final reposRoot = Directory(repoRoot).parent.path;
      final raw = _read(reposRoot);
      final today = _dateKey(DateTime.now());
      final day = (raw['days'] as Map<String, dynamic>?) ?? {};
      final entry =
          (day[today] as Map<String, dynamic>?) ?? <String, dynamic>{};
      final articles =
          ((entry['articles'] as List<dynamic>?) ?? const []).cast<String>();
      if (!articles.contains(relativePath)) articles.add(relativePath);
      entry['articles'] = articles;
      entry['minutes'] = ((entry['minutes'] as num?) ?? 0) + minutes;
      day[today] = entry;
      raw['days'] = day;
      _prune(raw);
      _write(reposRoot, raw);
    } on Object {
      // 统计失败不影响阅读
    }
  }

  /// 最近 [days] 天（含今天，旧→新）的逐日统计与合计。
  static ReadingWeeklySummary weeklySummary(String reposRoot, {int days = 7}) {
    final raw = _read(reposRoot);
    final dayMap = (raw['days'] as Map<String, dynamic>?) ?? {};
    final entries = <ReadingDayStat>[];
    var totalMinutes = 0.0;
    var totalArticles = 0;
    final now = DateTime.now();
    for (var i = days - 1; i >= 0; i--) {
      final date = DateTime(now.year, now.month, now.day - i);
      final key = _dateKey(date);
      final entry = dayMap[key] as Map<String, dynamic>?;
      final minutes = (entry?['minutes'] as num?)?.toDouble() ?? 0;
      final articles =
          ((entry?['articles'] as List<dynamic>?) ?? const []).length;
      entries.add(ReadingDayStat(date: date, minutes: minutes, articles: articles));
      totalMinutes += minutes;
      totalArticles += articles;
    }
    return ReadingWeeklySummary(
      days: entries,
      totalMinutes: totalMinutes,
      totalArticles: totalArticles,
    );
  }

  /// 推导 reposRoot（仓库根的上级目录），供阅读页调用方少传一个参数。
  static String reposRootOf(String repoRoot) =>
      Directory(repoRoot).parent.path;

  static Map<String, dynamic> _read(String reposRoot) {
    final f = _file(reposRoot);
    if (!f.existsSync()) return <String, dynamic>{};
    try {
      final d = jsonDecode(f.readAsStringSync());
      return d is Map<String, dynamic> ? d : <String, dynamic>{};
    } on Object {
      return <String, dynamic>{};
    }
  }

  static void _write(String reposRoot, Map<String, dynamic> raw) {
    final f = _file(reposRoot);
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(jsonEncode(raw));
  }

  static File _file(String reposRoot) => File(
      '$reposRoot${Platform.pathSeparator}.meta'
      '${Platform.pathSeparator}stats.json');

  /// 只保留最近 [_keepDays] 天。
  static void _prune(Map<String, dynamic> raw) {
    final dayMap = (raw['days'] as Map<String, dynamic>?) ?? {};
    if (dayMap.length <= _keepDays) return;
    final keys = dayMap.keys.toList()..sort();
    for (final k in keys.take(dayMap.length - _keepDays)) {
      dayMap.remove(k);
    }
  }

  static String _dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

/// 单日统计。
@immutable
class ReadingDayStat {
  const ReadingDayStat({
    required this.date,
    required this.minutes,
    required this.articles,
  });

  final DateTime date;
  final double minutes;
  final int articles;
}

/// 近一周汇总。
@immutable
class ReadingWeeklySummary {
  const ReadingWeeklySummary({
    required this.days,
    required this.totalMinutes,
    required this.totalArticles,
  });

  final List<ReadingDayStat> days;
  final double totalMinutes;
  final int totalArticles;

  /// 单日最大时长（条形图归一化用），全 0 时返回 1 避免除零。
  double get peakMinutes {
    var peak = 0.0;
    for (final d in days) {
      if (d.minutes > peak) peak = d.minutes;
    }
    return peak <= 0 ? 1 : peak;
  }
}
