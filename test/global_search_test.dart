import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader/src/ui/global_search_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 跨仓库搜索：结果按仓库分组；改仓库过滤后立即重跑。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late Directory repoA;
  late Directory repoB;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    root = Directory.systemTemp.createTempSync('global-search');
    repoA = Directory('${root.path}${Platform.pathSeparator}a')..createSync();
    repoB = Directory('${root.path}${Platform.pathSeparator}b')..createSync();
    File('${repoA.path}${Platform.pathSeparator}note.md')
        .writeAsStringSync('flutter state 在 a');
    File('${repoB.path}${Platform.pathSeparator}note.md')
        .writeAsStringSync('flutter state 在 b');
  });

  tearDown(() {
    try {
      if (root.existsSync()) root.deleteSync(recursive: true);
    } on Object {
      // 忽略
    }
  });

  Future<void> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(home: GlobalSearchPage(repos: [repoA, repoB])),
    );
    await tester.pump();
  }

  Future<void> settleSearch(WidgetTester tester, int debounceMs) async {
    await tester.pump(Duration(milliseconds: debounceMs));
    // 检索在 isolate 里逐仓库读盘：多给几轮真实异步时间，每轮后渲染一次
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)),
      );
      await tester.pump();
    }
  }

  testWidgets('groups hits by repo and re-runs when the filter changes',
      (tester) async {
    await pumpPage(tester);
    await tester.enterText(find.byType(TextField), 'flutter');
    await settleSearch(tester, 450);

    expect(find.byType(ListTile), findsNWidgets(2),
        reason: '两个仓库各命中一条');

    // 只选仓库 a：过滤条件变化的当下就应重跑，不需要再改查询
    await tester.tap(find.widgetWithText(FilterChip, 'a'));
    await settleSearch(tester, 250);
    expect(find.byType(ListTile), findsOneWidget);
  });
}
