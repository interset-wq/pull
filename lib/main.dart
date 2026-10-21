import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:git2dart/git2dart.dart';
import 'package:git2dart_binaries/git2dart_binaries.dart'
    show AndroidSSLHelper;

import 'src/ui/home_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isAndroid) {
    // 必须先初始化 libgit2，再配置 CA 证书路径；
    // Android 系统证书库对静态链接的 OpenSSL 不可达，不配置则 HTTPS 克隆
    // 报 "the SSL certificate is invalid"
    Libgit2.version;
    final certPath = await AndroidSSLHelper.initialize();
    Libgit2.setSSLCertLocations(file: certPath);
  }
  runApp(const ReaderApp());
}

class ReaderApp extends StatelessWidget {
  const ReaderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Reader',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
        pageTransitionsTheme: const PageTransitionsTheme(builders: {
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        }),
        snackBarTheme: const SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
        ),
        cardTheme: const CardThemeData(
          elevation: 0,
          clipBehavior: Clip.antiAlias,
        ),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        pageTransitionsTheme: const PageTransitionsTheme(builders: {
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        }),
        snackBarTheme: const SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
        ),
        cardTheme: const CardThemeData(
          elevation: 0,
          clipBehavior: Clip.antiAlias,
        ),
      ),
      home: const HomePage(),
    );
  }
}
