/// 代码场景统一字体：JetBrains Mono（VS Code 风格的代码友好字体），
/// 内置打包保证三端一致；可在设置中切换为系统字体 Consolas
/// （Windows 可用，移动端缺失时回退到内置 JetBrains Mono）。
library;

import 'package:flutter/material.dart';

import '../theme/app_prefs.dart';

const String kCodeFontJetBrains = 'JetBrains Mono';
const String kCodeFontConsolas = 'Consolas';

/// 设置页可选的代码字体。
const List<String> kCodeFontChoices = [kCodeFontJetBrains, kCodeFontConsolas];

const List<String> kCodeFontFallback = ['Consolas', 'Menlo', 'monospace'];

/// 指定字体的代码文本样式，配合 fontSize/height 使用。
/// 关闭连字（calt/liga 置 0）：`->` `===` 等序列会被合成
/// 箭头、横线字形，与源码字符不对应，阅读代码有歧义。
TextStyle codeFontStyle(String family) => TextStyle(
      fontFamily: family,
      fontFamilyFallback: family == kCodeFontConsolas
          ? ['JetBrains Mono', 'Menlo', 'monospace']
          : kCodeFontFallback,
      fontFeatures: const [FontFeature('calt', 0), FontFeature('liga', 0)],
    );

/// 当前设置生效的代码字体样式。
TextStyle currentCodeFontStyle() =>
    codeFontStyle(AppPrefs.instance?.codeFont ?? kCodeFontJetBrains);
