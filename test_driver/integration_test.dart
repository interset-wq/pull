import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

/// 性能基线的驱动：把 App 侧 `binding.reportData` 里的结果写成
/// `temp/perf_response.json`，不依赖控制台日志（flutter drive 的输出
/// 在部分终端里会被缓冲）。
Future<void> main() => integrationDriver(
      responseDataCallback: (data) async {
        final file = File('temp/perf_response.json');
        await file.parent.create(recursive: true);
        await file.writeAsString(
          const JsonEncoder.withIndent('  ').convert(data ?? const {}),
        );
        if (data != null) {
          for (final entry in data.entries) {
            // ignore: avoid_print
            print('${entry.key}: ${jsonEncode(entry.value)}');
          }
        }
      },
    );
