/// 代码场景统一字体：JetBrains Mono（VS Code 风格的代码友好字体），
/// 内置打包保证三端一致；缺失时回退到平台等宽字体。
library;

import 'package:flutter/material.dart';

const String kCodeFontFamily = 'JetBrains Mono';

const List<String> kCodeFontFallback = ['Consolas', 'Menlo', 'monospace'];

/// 代码文本样式的字体部分，配合 fontSize/height 使用。
const TextStyle kCodeFontStyle = TextStyle(
  fontFamily: kCodeFontFamily,
  fontFamilyFallback: kCodeFontFallback,
);
