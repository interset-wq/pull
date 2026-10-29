import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader/src/git/sync_service.dart';
import 'package:reader/src/ui/pull_progress.dart';

/// 拉取进度对话框：显示标题与对象/体积，动作结束后自动关闭。
void main() {
  testWidgets('shows progress and closes when the action finishes',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => runWithPullProgress<void>(
                  context,
                  title: '正在拉取',
                  action: (onProgress) async {
                    onProgress(
                      'notes',
                      const CloneProgress(
                        receivedObjects: 5,
                        totalObjects: 10,
                        receivedBytes: 2048,
                      ),
                    );
                    await Future<void>.delayed(
                      const Duration(milliseconds: 100),
                    );
                  },
                ),
                child: const Text('run'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('run'));
    await tester.pump();
    await tester.pump();
    expect(find.text('正在拉取'), findsOneWidget);
    expect(find.text('notes'), findsOneWidget);
    expect(find.textContaining('5 / 10 个对象'), findsOneWidget);
    expect(find.textContaining('2.0 KB'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('正在拉取'), findsNothing, reason: '动作结束后对话框应关闭');
  });

  testWidgets('shows an indeterminate bar before the first progress event',
      (tester) async {
    late BuildContext captured;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            captured = context;
            return const Scaffold(body: SizedBox());
          },
        ),
      ),
    );

    final future = runWithPullProgress<void>(
      captured,
      title: '正在更新全部仓库',
      action: (onProgress) async {
        await Future<void>.delayed(const Duration(seconds: 1));
      },
    );
    await tester.pump();
    expect(find.text('正在更新全部仓库'), findsOneWidget);
    expect(find.text('连接中…'), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 300));
    await future;
    expect(find.text('正在更新全部仓库'), findsNothing);
  });
}
