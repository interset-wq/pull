import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('app builds home page', (tester) async {
    await tester.pumpWidget(const ReaderApp());
    // 只推进固定帧数：仓库目录依赖 path_provider 插件（测试环境缺失），
    // 用 pumpAndSettle 会一直等首页的加载指示器
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    // 头部品牌已由文字改为 logo；设置/标签/更新收进「更多」菜单
    expect(find.byType(Scaffold), findsOneWidget);
    expect(find.byIcon(Icons.more_vert), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsOneWidget);

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('设置'), findsOneWidget);
    expect(find.text('标签'), findsOneWidget);
  });
}
