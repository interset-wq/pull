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
    // 头部品牌已由文字改为 logo；这里断言页面骨架而非具体文案
    expect(find.byType(Scaffold), findsOneWidget);
    expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsOneWidget);
  });
}
