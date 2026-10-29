import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader/src/platforms/git_platform.dart';
import 'package:reader/src/theme/app_prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 偏好设置：默认值、越界收敛、持久化与搜索历史。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppPrefs.resetForTest();
  });

  test('defaults', () async {
    final prefs = await AppPrefs.load();
    expect(prefs.mode, ThemeMode.system);
    expect(prefs.platform, GitPlatform.gitcode);
    expect(prefs.defaultOwner, '');
    expect(prefs.lineHeight, 1.75);
    expect(prefs.pageMargin, 16);
    expect(prefs.keepScreenOn, isTrue);
    expect(prefs.treeMode, isFalse);
    expect(prefs.dirTags, isTrue);
    expect(prefs.searchHistory, isEmpty);
  });

  test('clamps persisted values into safe ranges', () async {
    SharedPreferences.setMockInitialValues({
      'lineHeight': 9.0,
      'pageMargin': 2.0,
      'recentsLimit': 99,
      'appIcon': 'nope',
      // 旧版本曾用字符串存布尔：'0' 应被识别为 false
      'codeLineNumbers': '0',
    });
    final prefs = await AppPrefs.load();
    expect(prefs.lineHeight, 2.2);
    expect(prefs.pageMargin, 8.0);
    expect(prefs.recentsLimit, 20);
    expect(prefs.appIcon, 'book', reason: '非法图标回退默认');
    expect(prefs.codeLineNumbers, isFalse);
  });

  test('setters persist across a reload', () async {
    final prefs = await AppPrefs.load();
    await prefs.setMode(ThemeMode.dark);
    await prefs.setPlatform(GitPlatform.github);
    await prefs.setDefaultOwner('me');
    await prefs.setTreeMode(true);
    await prefs.setLineHeight(1.9);

    AppPrefs.resetForTest();
    final reloaded = await AppPrefs.load();
    expect(reloaded.mode, ThemeMode.dark);
    expect(reloaded.platform, GitPlatform.github);
    expect(reloaded.defaultOwner, 'me');
    expect(reloaded.treeMode, isTrue);
    expect(reloaded.lineHeight, 1.9);
  });

  test('search history dedupes, caps at 12 and can be removed', () async {
    final prefs = await AppPrefs.load();
    for (var i = 0; i < 15; i++) {
      await prefs.addSearchHistory('q$i');
    }
    expect(prefs.searchHistory.length, 12);
    expect(prefs.searchHistory.first, 'q14');

    await prefs.addSearchHistory('q5');
    expect(prefs.searchHistory.first, 'q5');
    expect(prefs.searchHistory.where((e) => e == 'q5').length, 1,
        reason: '重复查询应去重并移到最前');

    await prefs.removeSearchHistory('q5');
    expect(prefs.searchHistory.contains('q5'), isFalse);

    AppPrefs.resetForTest();
    final reloaded = await AppPrefs.load();
    expect(reloaded.searchHistory, prefs.searchHistory);
  });

  test('loading with corrupt values keeps startup safe', () async {
    SharedPreferences.setMockInitialValues({
      'lineHeight': 'not-a-double',
      'recentsLimit': 'many',
    });
    final prefs = await AppPrefs.load();
    // getDouble/getInt 抛类型异常后整体回退默认值，但不影响启动
    expect(prefs.lineHeight, 1.75);
    expect(prefs.recentsLimit, 5);
  });
}
