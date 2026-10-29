import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:reader/src/notes/note_scanner.dart';
import 'package:reader/src/ui/markdown_viewer.dart';

/// 长文渲染基线（阶段 1.1，见 Roadmap.agent.md）。
///
/// 在真机、profile 模式下跑：
/// ```bash
/// flutter drive --profile -d <deviceId> \
///   --driver=test_driver/integration_test.dart \
///   --target=integration_test/render_perf_test.dart
/// ```
///
/// 只看某一档（内存更干净）：
/// ```bash
/// ... --dart-define=PERF_SIZES=10000
/// ```
///
/// 量的三件事：
/// - firstFrameMs：从挂载页面到首屏出现正文标记的墙钟时间（当前正文是
///   整篇一次性布局，所以它 ≈ 全文解析 + 布局 + 首次上屏）；
/// - 滚动帧耗时：连续上滑时 build+raster 的 p50 / p95 与掉帧比例；
/// - 内存：挂载前 / 滚动后的进程 RSS。
///
/// 第一组数字会被冷启动污染，所以先跑一次 200 行热身、不记录。
/// 样本刻意不含 Mermaid 与图片（它们有独立的按需加载路径），
/// 目的是先量「整篇布局」这条主干。
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final sizes = const String.fromEnvironment(
    'PERF_SIZES',
    defaultValue: '500,1000,2000,5000,10000',
  ).split(',').map(int.parse).toList();

  testWidgets(
    'warm up',
    timeout: const Timeout(Duration(minutes: 8)),
    (tester) => _runCase(binding, tester, 200, report: false),
  );

  for (final lineCount in sizes) {
    testWidgets(
      'render perf: $lineCount lines',
      timeout: const Timeout(Duration(minutes: 8)),
      (tester) async {
        final row = await _runCase(binding, tester, lineCount, report: true);
        binding.reportData ??= <String, dynamic>{};
        binding.reportData!['perf_$lineCount'] = row;
        // ignore: avoid_print
        print('PERF|${row.entries.map((e) => '${e.key}=${e.value}').join('|')}');
      },
    );
  }
}

Future<Map<String, Object>> _runCase(
  IntegrationTestWidgetsFlutterBinding binding,
  WidgetTester tester,
  int lineCount, {
  required bool report,
}) async {
  final tmp = await Directory.systemTemp.createTemp('pullread_perf_$lineCount');
  addTearDown(() async {
    try {
      await tmp.delete(recursive: true);
    } on Object {
      // 清理失败不影响结果
    }
  });

  final content = buildPerfDocumentLines(lineCount).join('\n');
  final name = 'perf_$lineCount.md';
  final file = File('${tmp.path}${Platform.pathSeparator}$name');
  await file.writeAsString(content);

  final note = NoteFile(
    relativePath: name,
    absolutePath: file.path,
    modified: DateTime.now(),
    sizeBytes: content.length,
  );

  final frames = <FrameTiming>[];
  void onTimings(List<FrameTiming> timings) => frames.addAll(timings);
  binding.addTimingsCallback(onTimings);
  addTearDown(() => binding.removeTimingsCallback(onTimings));

  final rssBefore = ProcessInfo.currentRss;
  final watch = Stopwatch()..start();
  await tester.pumpWidget(_app(note, tmp.path));

  // 等首屏正文：FutureBuilder 拿到内容后才会出现标记段。
  final marker = find.textContaining('PERF-TOP-MARKER', findRichText: true);
  var firstFrameMs = -1;
  while (watch.elapsed < const Duration(minutes: 3)) {
    await tester.pump(const Duration(milliseconds: 4));
    if (marker.evaluate().isNotEmpty) {
      firstFrameMs = watch.elapsedMilliseconds;
      break;
    }
  }
  watch.stop();
  expect(marker, findsWidgets, reason: '$lineCount 行样本没有渲染出正文');

  // 等两帧让首屏稳定，再开始量滚动（排除首帧的构建成本）。
  await tester.pump(const Duration(milliseconds: 200));
  frames.clear();

  // 滚动驱动的目标：懒渲染下正文是 CustomScrollView；导出模式才是
  // SingleChildScrollView（这里只量正常阅读路径）。
  final scrollable = find.byType(CustomScrollView).first;
  for (var i = 0; i < 30; i++) {
    await tester.drag(scrollable, const Offset(0, -450));
    await tester.pump(const Duration(milliseconds: 16));
  }
  await tester.pump(const Duration(milliseconds: 400));

  final stats = _frameStats(frames);
  final rssAfter = ProcessInfo.currentRss;
  final row = <String, Object>{
    'lines': lineCount,
    'docKB': (content.length / 1024).round(),
    'firstFrameMs': firstFrameMs,
    'frames': stats.count,
    'p50ms': double.parse(stats.p50.toStringAsFixed(1)),
    'p95ms': double.parse(stats.p95.toStringAsFixed(1)),
    'jankPct': double.parse(stats.jankPct.toStringAsFixed(1)),
    'rssBeforeMB': (rssBefore / 1024 / 1024).round(),
    'rssAfterMB': (rssAfter / 1024 / 1024).round(),
    'rssDeltaMB': ((rssAfter - rssBefore) / 1024 / 1024).round(),
  };
  if (!report) row['warmup'] = true;
  return row;
}

Widget _app(NoteFile note, String repoRoot) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF4C8F56),
      ),
      home: MarkdownViewerPage(note: note, repoRoot: repoRoot),
    );

class _Stats {
  const _Stats(this.count, this.p50, this.p95, this.jankPct);

  final int count;
  final double p50;
  final double p95;
  final double jankPct;
}

/// build + raster 耗时统计（毫秒）；超过 16.7ms 记一帧掉帧。
_Stats _frameStats(List<FrameTiming> frames) {
  final ms = <double>[
    for (final f in frames)
      ((f.buildDuration + f.rasterDuration).inMicroseconds / 1000),
  ]..sort();
  if (ms.isEmpty) return const _Stats(0, 0, 0, 0);
  double at(double p) => ms[((ms.length - 1) * p).round()];
  final janky = ms.where((v) => v > 16.7).length;
  return _Stats(ms.length, at(0.5), at(0.95), janky * 100 / ms.length);
}

/// 生成长文样本：标题 / 段落 / 列表 / 围栏代码 / 表格 / 折叠块，
/// 行数受控。不含 Mermaid 与图片（它们有独立的按需加载路径）。
List<String> buildPerfDocumentLines(int targetLines) {
  final lines = <String>[
    '# 渲染性能样本（$targetLines 行）',
    '',
    'PERF-TOP-MARKER 这一段用于判断正文是否已经渲染出来。',
    '',
  ];
  var section = 0;
  while (lines.length < targetLines) {
    section++;
    lines
      ..add('## 第 $section 节 · 一个长度接近真实笔记的标题')
      ..add('');
    for (var p = 1; p <= 5 && lines.length < targetLines; p++) {
      lines
        ..add('这是第 $section 节的第 $p 段正文，用来模拟真实笔记里的中文长段落，'
            '包含行内代码 `flutter analyze` 与**加粗**、*斜体*。')
        ..add('')
        ..add('A mixed paragraph with English words and 中文，用来测中英混排的行高与断行。')
        ..add('');
    }
    if (section % 4 == 0 && lines.length < targetLines) {
      lines
        ..add('```dart')
        ..add('Future<void> section$section() async {')
        ..add('  final value = await compute(_work, $section);')
        ..add('  debugPrint(value);')
        ..add('}')
        ..add('```')
        ..add('');
    }
    if (section % 6 == 0 && lines.length < targetLines) {
      lines
        ..add('| 字段 | 说明 | 示例 |')
        ..add('| --- | --- | --- |')
        ..add('| id | 编号 | $section |')
        ..add('| name | 名称 | 性能样本 |')
        ..add('');
    }
    if (section % 9 == 0 && lines.length < targetLines) {
      lines
        ..add('<details><summary>展开一段说明</summary>')
        ..add('')
        ..add('折叠块内部的正文，用于验证 details 的渲染成本。')
        ..add('')
        ..add('</details>')
        ..add('');
    }
    if (section % 8 == 0 && lines.length < targetLines) {
      lines
        ..add('- 列表项 A：一个条目')
        ..add('- 列表项 B：另一个条目')
        ..add('- 列表项 C：带 `code` 的条目')
        ..add('');
    }
  }
  return lines;
}
