import 'dart:convert';

import 'package:fast_gbk/fast_gbk.dart';

/// 文本文件解码（Roadmap「本地 TXT」）：UTF-8 优先（严格校验），
/// 非法字节时回退 GBK——中文小说/笔记常见 GBK/GB2312 编码，
/// 直接按 UTF-8 读会得到乱码。纯 Dart 实现，全平台可用。
String decodeTextBytes(List<int> bytes) {
  // UTF-8 BOM：去掉后再解，避免正文首字符残留 \uFEFF
  if (bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF) {
    return utf8.decode(bytes.sublist(3));
  }
  try {
    return utf8.decode(bytes); // 严格模式，非法字节抛 FormatException
  } on FormatException {
    return gbk.decode(bytes);
  }
}
