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
  /// 偏好只是"锦上添花"：读取失败或超时一律回退默认值，绝不阻塞启动。
  static Future<AppPrefs> load() async {
    if (_instance != null) return _instance!;
    ThemeMode mode = ThemeMode.system;
    try {
      final sp =
          await SharedPreferences.getInstance().timeout(const Duration(seconds: 3));
      mode = switch (sp.getString(_modeKey)) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
    } on Object {
      // 保持默认（跟随系统）
    }
    return _instance = AppPrefs._(mode);
  }

  Future<void> setMode(ThemeMode m) async {
    if (m == _mode) return;
    _mode = m;
    notifyListeners();
    try {
      final sp = await SharedPreferences.getInstance().timeout(const Duration(seconds: 3));
      await sp.setString(_modeKey, m.name);
    } on Object {
      // 保存失败不影响本次会话的主题切换
    }
  }

  /// 阅读字号索引持久化（越界值由调用方校验）。
  static Future<int> loadFontIndex() async {
    try {
      final sp =
          await SharedPreferences.getInstance().timeout(const Duration(seconds: 3));
      return sp.getInt(_fontKey) ?? 1;
    } on Object {
      return 1;
    }
  }

  static Future<void> saveFontIndex(int index) async {
    try {
      final sp =
          await SharedPreferences.getInstance().timeout(const Duration(seconds: 3));
      await sp.setInt(_fontKey, index);
    } on Object {
      // 忽略
    }
  }
}
