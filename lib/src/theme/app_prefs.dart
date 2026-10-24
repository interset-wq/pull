import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../platforms/git_platform.dart';
import '../ui/code_font.dart'
    show kCodeFontChoices, kCodeFontJetBrains;

/// 应用级用户偏好：主题模式（跟随系统/浅/暗，持久化 + 应用内即时切换）、
/// 阅读字号（持久化）与克隆偏好（默认平台 + 默认用户名，
/// 供克隆时用短输入 `repo` / `owner/repo` 自动拼接完整 URL）。
class AppPrefs extends ChangeNotifier {
  AppPrefs._(
    this._mode,
    this._platform,
    this._defaultOwner,
    this._codeFont,
    this._keepScreenOn,
    this._codeLineNumbers,
    this._codeFoldThreshold,
  );

  static const _modeKey = 'themeMode';
  static const _fontKey = 'fontIndex';
  static const _platformKey = 'gitPlatform';
  static const _ownerKey = 'defaultOwner';
  static const _codeFontKey = 'codeFont';
  static const _keepScreenOnKey = 'keepScreenOn';
  static const _codeLineNumbersKey = 'codeLineNumbers';
  static const _codeFoldThresholdKey = 'codeFoldThreshold';

  ThemeMode _mode;
  ThemeMode get mode => _mode;

  GitPlatform _platform;
  GitPlatform get platform => _platform;

  String _defaultOwner;
  String get defaultOwner => _defaultOwner;

  String _codeFont;
  String get codeFont => _codeFont;

  bool _keepScreenOn;
  bool get keepScreenOn => _keepScreenOn;

  // 新增字段声明为可空：热重载会保留旧实例，旧实例构造时没有这些
  // 参数（值为 null），getter 必须兜底默认值，否则整页崩溃。
  bool? _codeLineNumbers;
  bool get codeLineNumbers => _codeLineNumbers ?? true;

  int? _codeFoldThreshold;
  int get codeFoldThreshold => _codeFoldThreshold ?? 30;

  static AppPrefs? _instance;
  static AppPrefs? get instance => _instance;

  /// 启动时读取持久化设置（幂等，重复调用返回同一实例）。
  /// 偏好只是"锦上添花"：读取失败或超时一律回退默认值，绝不阻塞启动。
  static Future<AppPrefs> load() async {
    if (_instance != null) return _instance!;
    ThemeMode mode = ThemeMode.system;
    var platform = GitPlatform.gitcode;
    var owner = '';
    var codeFont = kCodeFontJetBrains;
    var keepScreenOn = false;
    var codeLineNumbers = true;
    var codeFoldThreshold = 30;
    try {
      final sp =
          await SharedPreferences.getInstance().timeout(const Duration(seconds: 3));
      mode = switch (sp.getString(_modeKey)) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
      platform = GitPlatform.values.firstWhere(
        (p) => p.name == sp.getString(_platformKey),
        orElse: () => GitPlatform.gitcode,
      );
      owner = sp.getString(_ownerKey) ?? '';
      codeFont = kCodeFontChoices.contains(sp.getString(_codeFontKey))
          ? sp.getString(_codeFontKey)!
          : kCodeFontJetBrains;
      keepScreenOn = sp.getBool(_keepScreenOnKey) ?? false;
      codeLineNumbers = sp.getBool(_codeLineNumbersKey) ?? true;
      codeFoldThreshold = sp.getInt(_codeFoldThresholdKey) ?? 30;
    } on Object {
      // 保持默认（跟随系统 + GitCode）
    }
    return _instance = AppPrefs._(
      mode,
      platform,
      owner,
      codeFont,
      keepScreenOn,
      codeLineNumbers,
      codeFoldThreshold.clamp(10, 200),
    );
  }

  Future<void> setMode(ThemeMode m) async {
    if (m == _mode) return;
    _mode = m;
    notifyListeners();
    await _save(_modeKey, m.name);
  }

  Future<void> setPlatform(GitPlatform p) async {
    if (p == _platform) return;
    _platform = p;
    notifyListeners();
    await _save(_platformKey, p.name);
  }

  Future<void> setDefaultOwner(String v) async {
    final value = v.trim();
    if (value == _defaultOwner) return;
    _defaultOwner = value;
    notifyListeners();
    await _save(_ownerKey, value);
  }

  Future<void> setCodeFont(String font) async {
    if (font == _codeFont) return;
    _codeFont = font;
    notifyListeners();
    await _save(_codeFontKey, font);
  }

  Future<void> setKeepScreenOn(bool v) async {
    if (v == _keepScreenOn) return;
    _keepScreenOn = v;
    notifyListeners();
    try {
      final sp =
          await SharedPreferences.getInstance().timeout(const Duration(seconds: 3));
      await sp.setBool(_keepScreenOnKey, v);
    } on Object {
      // 保存失败不影响本次会话
    }
  }

  Future<void> setCodeLineNumbers(bool v) async {
    if (v == codeLineNumbers) return;
    _codeLineNumbers = v;
    notifyListeners();
    await _save(_codeLineNumbersKey, v ? '1' : '0');
  }

  Future<void> setCodeFoldThreshold(int lines) async {
    final value = lines.clamp(10, 200);
    if (value == codeFoldThreshold) return;
    _codeFoldThreshold = value;
    notifyListeners();
    try {
      final sp =
          await SharedPreferences.getInstance().timeout(const Duration(seconds: 3));
      await sp.setInt(_codeFoldThresholdKey, value);
    } on Object {
      // 保存失败不影响本次会话
    }
  }

  Future<void> _save(String key, String value) async {
    try {
      final sp =
          await SharedPreferences.getInstance().timeout(const Duration(seconds: 3));
      await sp.setString(key, value);
    } on Object {
      // 保存失败不影响本次会话
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
