import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    this._codeFoldEnabled,
    this._recentsLimit,
  );

  static const _modeKey = 'themeMode';
  static const _fontKey = 'fontIndex';
  static const _platformKey = 'gitPlatform';
  static const _ownerKey = 'defaultOwner';
  static const _codeFontKey = 'codeFont';
  static const _keepScreenOnKey = 'keepScreenOn';
  static const _codeLineNumbersKey = 'codeLineNumbers';
  static const _codeFoldThresholdKey = 'codeFoldThreshold';
  static const _codeFoldEnabledKey = 'codeFoldEnabled';
  static const _recentsLimitKey = 'recentsLimit';
  static const _appIconKey = 'appIcon';
  static const _swipePagingKey = 'swipePaging';
  static const _wideTableKey = 'wideTable';
  static const _ignoreDefaultsKey = 'ignoreDefaults';
  static const _ignoreRulesKey = 'ignoreRules';

  /// 应用图标可选值（与 AndroidManifest activity-alias 对应）。
  static const kAppIconKeys = ['book', 'page', 'arrow', 'converge', 'tray'];

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

  // 同 codeLineNumbers：热重载会保留无此参数的旧实例（字段为 null），
  // getter 兜底默认值，set 前用 getter 比较
  bool? _codeFoldEnabled;
  bool get codeFoldEnabled => _codeFoldEnabled ?? true;

  // 同 codeLineNumbers：热重载会保留无此参数的旧实例（字段为 null），
  // getter 兜底默认值
  int? _recentsLimit;
  int get recentsLimit => _recentsLimit ?? 5;

  // 手势翻页开关：默认关闭（易与代码块/表格横滑混淆，交由用户显式开启）
  bool? _swipePaging;
  bool get swipePaging => _swipePaging ?? false;

  // 表格自然宽度开关：开启后表格始终按内容固有宽度渲染、超出视口横向
  // 滚动（v0.1.0 行为，单元格不换行）；默认关闭——超宽表格自动切换为
  // 按比例分摊的换行档（7e42d04 行为）
  bool? _wideTable;
  bool get wideTable => _wideTable ?? false;

  // Ignore 配置（Roadmap「设置增强·Ignore 配置」）：默认隐藏规则开关
  // （.git/.gitignore/.github/node_modules/点开头名，见 NoteScanner）+
  // 自定义文件/目录名规则（按名字精确匹配，跨仓库生效）
  bool? _ignoreDefaults;
  bool get ignoreDefaults => _ignoreDefaults ?? true;

  List<String>? _ignoreRules;
  List<String> get ignoreRules => _ignoreRules ?? const [];

  // 应用图标：'book'（摊开书，默认）/ 'page'（页即箭）/ 'arrow'（抽页成箭）
  String? _appIcon;
  String get appIcon =>
      _appIcon != null && kAppIconKeys.contains(_appIcon) ? _appIcon! : 'book';

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
    var codeFoldEnabled = true;
    var recentsLimit = 5;
    var appIcon = 'book';
    var swipePaging = false;
    var wideTable = false;
    var ignoreDefaults = true;
    var ignoreRules = const <String>[];
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
      // 旧版本曾用 setString 存 '1'/'0'，getBool 会抛类型异常被吞掉
      // 回退默认——兼容两种存量形态
      codeLineNumbers = switch (sp.get(_codeLineNumbersKey)) {
        final bool b => b,
        final String s => s != '0',
        _ => true,
      };
      codeFoldThreshold = sp.getInt(_codeFoldThresholdKey) ?? 30;
      codeFoldEnabled = sp.getBool(_codeFoldEnabledKey) ?? true;
      recentsLimit = (sp.getInt(_recentsLimitKey) ?? 5).clamp(1, 20);
      appIcon = sp.getString(_appIconKey) ?? 'book';
      swipePaging = sp.getBool(_swipePagingKey) ?? false;
      wideTable = sp.getBool(_wideTableKey) ?? false;
      ignoreDefaults = sp.getBool(_ignoreDefaultsKey) ?? true;
      ignoreRules = sp.getStringList(_ignoreRulesKey) ?? const <String>[];
    } on Object {
      // 保持默认（跟随系统 + GitCode）
    }
    final prefs = AppPrefs._(
      mode,
      platform,
      owner,
      codeFont,
      keepScreenOn,
      codeLineNumbers,
      codeFoldThreshold.clamp(10, 200),
      codeFoldEnabled,
      recentsLimit,
    );
    prefs._appIcon = appIcon;
    prefs._swipePaging = swipePaging;
    prefs._wideTable = wideTable;
    prefs._ignoreDefaults = ignoreDefaults;
    prefs._ignoreRules = ignoreRules;
    return _instance = prefs;
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
    try {
      final sp =
          await SharedPreferences.getInstance().timeout(const Duration(seconds: 3));
      await sp.setBool(_codeLineNumbersKey, v);
    } on Object {
      // 保存失败不影响本次会话
    }
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

  Future<void> setCodeFoldEnabled(bool v) async {
    if (v == codeFoldEnabled) return;
    _codeFoldEnabled = v;
    notifyListeners();
    try {
      final sp =
          await SharedPreferences.getInstance().timeout(const Duration(seconds: 3));
      await sp.setBool(_codeFoldEnabledKey, v);
    } on Object {
      // 保存失败不影响本次会话
    }
  }

  Future<void> setRecentsLimit(int v) async {
    final clamped = v.clamp(1, 20);
    if (clamped == recentsLimit) return;
    _recentsLimit = clamped;
    notifyListeners();
    try {
      final sp =
          await SharedPreferences.getInstance().timeout(const Duration(seconds: 3));
      await sp.setInt(_recentsLimitKey, clamped);
    } on Object {
      // 保存失败不影响本次会话
    }
  }

  Future<void> setSwipePaging(bool v) async {
    if (v == swipePaging) return;
    _swipePaging = v;
    notifyListeners();
    try {
      final sp =
          await SharedPreferences.getInstance().timeout(const Duration(seconds: 3));
      await sp.setBool(_swipePagingKey, v);
    } on Object {
      // 保存失败不影响本次会话
    }
  }

  Future<void> setWideTable(bool v) async {
    if (v == wideTable) return;
    _wideTable = v;
    notifyListeners();
    try {
      final sp =
          await SharedPreferences.getInstance().timeout(const Duration(seconds: 3));
      await sp.setBool(_wideTableKey, v);
    } on Object {
      // 保存失败不影响本次会话
    }
  }

  Future<void> setIgnoreDefaults(bool v) async {
    if (v == ignoreDefaults) return;
    _ignoreDefaults = v;
    notifyListeners();
    try {
      final sp =
          await SharedPreferences.getInstance().timeout(const Duration(seconds: 3));
      await sp.setBool(_ignoreDefaultsKey, v);
    } on Object {
      // 保存失败不影响本次会话
    }
  }

  Future<void> setIgnoreRules(List<String> v) async {
    _ignoreRules = List.unmodifiable(v);
    notifyListeners();
    try {
      final sp =
          await SharedPreferences.getInstance().timeout(const Duration(seconds: 3));
      await sp.setStringList(_ignoreRulesKey, v);
    } on Object {
      // 保存失败不影响本次会话
    }
  }

  /// 恢复默认：清空自定义规则并恢复默认隐藏规则开关。
  Future<void> resetIgnoreRules() async {
    _ignoreRules = const [];
    _ignoreDefaults = true;
    notifyListeners();
    try {
      final sp =
          await SharedPreferences.getInstance().timeout(const Duration(seconds: 3));
      await sp.remove(_ignoreRulesKey);
      await sp.setBool(_ignoreDefaultsKey, true);
    } on Object {
      // 保存失败不影响本次会话
    }
  }

  /// 切换应用图标（Android activity-alias，经原生通道）；
  /// 其他平台无原生实现，仅持久化偏好。
  Future<void> setAppIcon(String key) async {
    if (!kAppIconKeys.contains(key) || key == appIcon) return;
    _appIcon = key;
    notifyListeners();
    await _save(_appIconKey, key);
    try {
      await const MethodChannel('app_icon')
          .invokeMethod<bool>('setIcon', {'icon': key});
    } on Object {
      // Windows / 预览环境：通道不存在，忽略
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
