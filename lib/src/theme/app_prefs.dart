import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 应用级用户偏好：主题模式（跟随系统/浅/暗，持久化 + 应用内即时切换）
/// 与阅读字号（持久化）。
class AppPrefs extends ChangeNotifier {
  AppPrefs._(this._mode);

  static const _modeKey = 'themeMode';
  static const _fontKey = 'fontIndex';

  ThemeMode _mode;
  ThemeMode get mode => _mode;

  static AppPrefs? _instance;
  static AppPrefs? get instance => _instance;

  /// 启动时读取持久化设置（幂等，重复调用返回同一实例）。
  static Future<AppPrefs> load() async {
    if (_instance != null) return _instance!;
    final sp = await SharedPreferences.getInstance();
    final mode = switch (sp.getString(_modeKey)) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    return _instance = AppPrefs._(mode);
  }

  Future<void> setMode(ThemeMode m) async {
    if (m == _mode) return;
    _mode = m;
    notifyListeners();
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_modeKey, m.name);
  }

  /// 阅读字号索引持久化（越界值由调用方校验）。
  static Future<int> loadFontIndex() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getInt(_fontKey) ?? 1;
  }

  static Future<void> saveFontIndex(int index) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setInt(_fontKey, index);
  }
}
