import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader/src/ui/home_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 仓库页搜索框：文件名过滤与「文件名 / 正文」切换。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('search filters by file name and toggles content mode',
      (tester) async {
    final repo = Directory.systemTemp.createTempSync('repo-search-ui');
    addTearDown(() {
      if (repo.existsSync()) repo.deleteSync(recursive: true);
    });
    File('${repo.path}${Platform.pathSeparator}alpha.md')
        .writeAsStringSync('# alpha\n\n正文里有 Flutter 关键字');
    File('${repo.path}${Platform.pathSeparator}beta.md')
        .writeAsStringSync('# beta\n\n别的正文');

    await tester.pumpWidget(
      MaterialApp(home: RepoPage(repoDir: repo)),
    );
    // 后台 isolate 扫描需要真实异步时间
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 400)),
    );
    await tester.pump();

    expect(find.text('alpha.md'), findsWidgets);
    expect(find.text('beta.md'), findsWidgets);

    await tester.enterText(find.byType(TextField).first, 'alp');
    await tester.pump();
    expect(find.text('alpha.md'), findsWidgets);
    expect(find.text('beta.md'), findsNothing);

    // 切到正文模式：输入不变，结果改为正文命中
    await tester.tap(find.byTooltip('搜索正文'));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 600)),
    );
    await tester.pump();
    expect(find.text('alpha.md'), findsWidgets);
    expect(find.text('beta.md'), findsNothing);

    // 清空后回到普通目录列表
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    expect(find.text('beta.md'), findsWidgets);
  });
}

