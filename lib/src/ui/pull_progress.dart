import 'dart:async';

import 'package:flutter/material.dart';

import '../git/sync_service.dart';
import '../utils/dir_size.dart';

/// 拉取进度：一行说明（第几个仓库/哪个仓库）+ 可选的对象传输快照。
class PullProgressState {
  const PullProgressState(this.label, [this.progress]);

  final String label;
  final CloneProgress? progress;
}

/// 在对话框里跑一次拉取/批量拉取，实时显示对象数与已传输体积。
///
/// 拉取不可安全取消（fetch 是阻塞原生调用，kill 可能留下半截 packfile），
/// 所以不提供取消按钮；超时与失败由调用方处理，这里只负责收尾关窗。
/// [action] 通过 `onProgress` 汇报进度；返回后对话框自动关闭。
Future<T> runWithPullProgress<T>(
  BuildContext context, {
  required String title,
  required Future<T> Function(
    void Function(String label, CloneProgress? progress) onProgress,
  ) action,
}) async {
  final notifier = ValueNotifier<PullProgressState>(
    const PullProgressState('连接中…'),
  );
  var dialogOpen = false;
  late BuildContext dialogContext;
  final dialog = showDialog<void>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: false,
    builder: (ctx) {
      dialogOpen = true;
      dialogContext = ctx;
      return PopScope(
        canPop: false,
        child: AlertDialog(
          title: Text(title),
          content: ValueListenableBuilder<PullProgressState>(
            valueListenable: notifier,
            builder: (context, state, _) {
              final p = state.progress;
              final fraction = p?.fraction;
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LinearProgressIndicator(value: fraction),
                  const SizedBox(height: 12),
                  Text(state.label),
                  if (p != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      fraction == null
                          ? formatBytes(p.receivedBytes)
                          : '${p.receivedObjects} / ${p.totalObjects} 个对象 · '
                              '${formatBytes(p.receivedBytes)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      );
    },
  );
  unawaited(dialog.whenComplete(() => dialogOpen = false));
  // 等一帧确保对话框已入栈：极快的 pull（已是最新）也不会把对话框留到后面
  await WidgetsBinding.instance.endOfFrame;
  try {
    return await action(
      (label, progress) =>
          notifier.value = PullProgressState(label, progress),
    );
  } finally {
    if (dialogOpen && dialogContext.mounted) {
      Navigator.of(dialogContext).pop();
    }
    notifier.dispose();
  }
}
