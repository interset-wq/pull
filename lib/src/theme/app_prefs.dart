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
  static const _lineHeightKey = 'lineHeight';
  static const _pageMarginKey = 'pageMargin';
  static const _codeFoldEnabledKey = 'codeFoldEnabled';
  static const _recentsLimitKey = 'recentsLimit';
  static const _appIconKey = 'appIcon';
  static const _swipePagingKey = 'swipePaging';
  static const _wideTableKey = 'wideTable';
  static const _ignoreDefaultsKey = 'ignoreDefaults';
  static const _ignoreRulesKey = 'ignoreRules';
  static const _detailsExpandedKey = 'detailsExpanded';
  static const _silentPullKey = 'silentPull';
  static const _treeModeKey = 'treeMode';

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

  // 阅读排版：正文行距（倍数，默认 1.75）与水平页边距（逻辑像素，默认 16）。
  // 同 codeLineNumbers：热重载会保留无此参数的旧实例（字段为 null），
  // getter 兜底默认值，set 前用 getter 比较
  double? _lineHeight;
  double get lineHeight => _lineHeight ?? 1.75;

  double? _pageMargin;
  double get pageMargin => _pageMargin ?? 16;

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
  // 滚动（v0.1.0 行为，单元格不换行）；默认开启——关闭时超宽表格自动
  // 切换为按比例分摊的换行档（7e42d04 行为）
  bool? _wideTable;
  bool get wideTable => _wideTable ?? true;

  // Ignore 配置（Roadmap「设置增强·Ignore 配置」）：默认隐藏规则开关
  // （点开头的文件/目录名，.git 恒忽略，见 NoteScanner）+
  // 自定义文件/目录名规则（按名字精确匹配，跨仓库生效）
  bool? _ignoreDefaults;
  bool get ignoreDefaults => _ignoreDefaults ?? true;

  List<String>? _ignoreRules;
  List<String> get ignoreRules => _ignoreRules ?? const [];

  // 折叠块（<details>）默认是否展开（未显式 open 时），默认展开
  bool? _detailsExpanded;
  bool get detailsExpanded => _detailsExpanded ?? true;

  // 启动时后台静默 pull 所有仓库：默认关闭——pull 逻辑简单，下拉刷新
  // 即可手动同步，自动 pull 意义不大
  bool? _silentPull;
  bool get silentPull => _silentPull ?? false;

  // 仓库页目录树模式：目录就地展开/折叠。默认关闭——经典模式（点目录
  // 进入下一页，类似文件资源管理器）才是主要导航方式，树模式下目录
  // 没有独立路由，指向目录的本地链接无法跳转
  bool? _treeMode;
  bool get treeMode => _treeMode ?? false;

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
    var keepScreenOn = true;
    var codeLineNumbers = true;
    var codeFoldThreshold = 30;
    var lineHeight = 1.75;
    var pageMargin = 16.0;
    var codeFoldEnabled = true;
    var recentsLimit = 5;
    var appIcon = 'book';
    var swipePaging = false;
    var wideTable = true;
    var ignoreDefaults = true;
    var ignoreRules = const <String>[];
    var detailsExpanded = true;
    var silentPull = false;
    var treeMode = false;
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
      keepScreenOn = sp.getBool(_keepScreenOnKey) ?? true;
      // 旧版本曾用 setString 存 '1'/'0'，getBool 会抛类型异常被吞掉
      // 回退默认——兼容两种存量形态
      codeLineNumbers = switch (sp.get(_codeLineNumbersKey)) {
        final bool b => b,
        final String s => s != '0',
        _ => true,
      };
      codeFoldThreshold = sp.getInt(_codeFoldThresholdKey) ?? 30;
      lineHeight = (sp.getDouble(_lineHeightKey) ?? 1.75).clamp(1.4, 2.2);
      pageMargin = (sp.getDouble(_pageMarginKey) ?? 16.0).clamp(8.0, 32.0);
      codeFoldEnabled = sp.getBool(_codeFoldEnabledKey) ?? true;
      recentsLimit = (sp.getInt(_recentsLimitKey) ?? 5).clamp(1, 20);
      appIcon = sp.getString(_appIconKey) ?? 'book';
      swipePaging = sp.getBool(_swipePagingKey) ?? false;
      wideTable = sp.getBool(_wideTableKey) ?? true;
      ignoreDefaults = sp.getBool(_ignoreDefaultsKey) ?? true;
      ignoreRules = sp.getStringList(_ignoreRulesKey) ?? const <String>[];
      detailsExpanded = sp.getBool(_detailsExpandedKey) ?? true;
      silentPull = sp.getBool(_silentPullKey) ?? false;
      treeMode = sp.getBool(_treeModeKey) ?? false;
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
    prefs._lineHeight = lineHeight;
    prefs._pageMargin = pageMargin;
    prefs._swipePaging = swipePaging;
    prefs._wideTable = wideTable;
    prefs._ignoreDefaults = ignoreDefaults;
    prefs._ignoreRules = ignoreRules;
    prefs._detailsExpanded = detailsExpanded;
    prefs._silentPull = silentPull;
    prefs._treeMode = treeMode;
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

  Future<void> setLineHeight(double v) async {
    final value = v.clamp(1.4, 2.2);
    if (value == lineHeight) return;
    _lineHeight = value;
    notifyListeners();
    try {
      final sp =
          await SharedPreferences.getInstance().timeout(const Duration(seconds: 3));
      await sp.setDouble(_lineHeightKey, value);
    } on Object {
      // 保存失败不影响本次会话
    }
  }

  Future<void> setPageMargin(double v) async {
    final value = v.clamp(8.0, 32.0);
    if (value == pageMargin) return;
    _pageMargin = value;
    notifyListeners();
    try {
      final sp =
          await SharedPreferences.getInstance().timeout(const Duration(seconds: 3));
      await sp.setDouble(_pageMarginKey, value);
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

  Future<void> setDetailsExpanded(bool v) async {
    if (v == detailsExpanded) return;
    _detailsExpanded = v;
    notifyListeners();
    try {
      final sp =
          await SharedPreferences.getInstance().timeout(const Duration(seconds: 3));
      await sp.setBool(_detailsExpandedKey, v);
    } on Object {
      // 保存失败不影响本次会话
    }
  }

  Future<void> setSilentPull(bool v) async {
    if (v == silentPull) return;
    _silentPull = v;
    notifyListeners();
    try {
      final sp =
          await SharedPreferences.getInstance().timeout(const Duration(seconds: 3));
      await sp.setBool(_silentPullKey, v);
    } on Object {
      // 保存失败不影响本次会话
    }
  }

  Future<void> setTreeMode(bool v) async {
    if (v == treeMode) return;
    _treeMode = v;
    notifyListeners();
    try {
      final sp =
          await SharedPreferences.getInstance().timeout(const Duration(seconds: 3));
      await sp.setBool(_treeModeKey, v);
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
