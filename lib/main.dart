import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:git2dart/git2dart.dart';
import 'package:git2dart_binaries/git2dart_binaries.dart'
    show AndroidSSLHelper;

import 'src/theme/app_prefs.dart';
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

class ReaderApp extends StatefulWidget {
  const ReaderApp({super.key});

  @override
  State<ReaderApp> createState() => _ReaderAppState();
}

class _ReaderAppState extends State<ReaderApp> {
  late final Future<AppPrefs> _prefs;

  @override
  void initState() {
    super.initState();
    _prefs = AppPrefs.load();
  }

  @override
  Widget build(BuildContext context) {
    const transitions = PageTransitionsTheme(builders: {
      TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
    });
    const snackbar = SnackBarThemeData(behavior: SnackBarBehavior.floating);
    const card = CardThemeData(elevation: 0, clipBehavior: Clip.antiAlias);
    return FutureBuilder<AppPrefs>(
      future: _prefs,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          // 加载态位于 MaterialApp 之上，没有 Directionality 祖先，不能直接用 Scaffold
          return const Directionality(
            textDirection: TextDirection.ltr,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final prefs = snapshot.data!;
        // 主题切换（App 内菜单）即时生效：随 AppPrefs 重建 MaterialApp
        return ListenableBuilder(
          listenable: prefs,
          builder: (context, _) => MaterialApp(
            title: 'Reader',
            theme: ThemeData(
              colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
              useMaterial3: true,
              pageTransitionsTheme: transitions,
              snackBarTheme: snackbar,
              cardTheme: card,
            ),
            darkTheme: ThemeData(
              colorScheme: ColorScheme.fromSeed(
                seedColor: Colors.teal,
                brightness: Brightness.dark,
              ),
              useMaterial3: true,
              pageTransitionsTheme: transitions,
              snackBarTheme: snackbar,
              cardTheme: card,
            ),
            themeMode: prefs.mode,
            home: const HomePage(),
          ),
        );
      },
    );
  }
}
