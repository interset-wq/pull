import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../git/repo_meta.dart';
import '../utils/dir_size.dart';

/// 存储占用页：展示应用数据各目录的磁盘占用，提供安全范围内的单项清理。
///
/// 四类目录都在应用文档目录下：
/// - `repos/`  克隆的 git 仓库（删除请在首页管理，这里只读展示）
/// - `local/`  本地文件夹镜像（删除请解除授权，这里只读展示）
/// - `imgcache/` 远程图片磁盘缓存（可整体清理，会重新下载）
/// - `.meta/`  元数据（阅读进度/收藏/索引等；清理阅读历史/收藏另有入口）
class StoragePage extends StatefulWidget {
  const StoragePage({super.key});

  @override
  State<StoragePage> createState() => _StoragePageState();
}

class _StoragePageState extends State<StoragePage> {
  String _reposRoot = '';
  bool _loading = true;
  int _reposBytes = 0;
  int _localBytes = 0;
  int _imgCacheBytes = 0;
  int _metaBytes = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final docs = await getApplicationDocumentsDirectory();
    final sep = Platform.pathSeparator;
    final reposRoot = '${docs.path}${sep}repos';
    final localRoot = '${docs.path}${sep}local';
    final imgRoot = '${docs.path}${sep}imgcache';
    final metaRoot = '${docs.path}$sep.meta';
    final sizes = await Future.wait([
      dirSizeInBackground(reposRoot),
      dirSizeInBackground(localRoot),
      dirSizeInBackground(imgRoot),
      dirSizeInBackground(metaRoot),
    ]);
    if (!mounted) return;
    setState(() {
      _reposRoot = reposRoot;
      _reposBytes = sizes[0];
      _localBytes = sizes[1];
      _imgCacheBytes = sizes[2];
      _metaBytes = sizes[3];
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('存储占用')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                _row(
                  theme,
                  icon: Icons.book_outlined,
                  title: '仓库',
                  subtitle: '克隆的 git 仓库内容；在首页的仓库卡片上删除单个仓库',
                  bytes: _reposBytes,
                ),
                _row(
                  theme,
                  icon: Icons.folder_copy_outlined,
                  title: '本地文件夹镜像',
                  subtitle: '授权文件夹的只读镜像；在首页删除对应条目即可释放',
                  bytes: _localBytes,
                ),
                _row(
                  theme,
                  icon: Icons.image_outlined,
                  title: '图片缓存',
                  subtitle: '文章里网络图片的离线副本；清理后重新联网加载',
                  bytes: _imgCacheBytes,
                  action: _imgCacheBytes > 0 ? '清理' : null,
                  onAction: _clearImageCache,
                ),
                _row(
                  theme,
                  icon: Icons.dataset_outlined,
                  title: '元数据',
                  subtitle: '阅读进度、收藏、文件索引与更新标记；清空阅读历史可释放部分',
                  bytes: _metaBytes,
                  action: '清空阅读历史',
                  onAction: () => _clearHistory(context),
                ),
                const SizedBox(height: 8),
                Text(
                  '总占用 ${formatBytes(_reposBytes + _localBytes + _imgCacheBytes + _metaBytes)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
    );
  }

  Widget _row(
    ThemeData theme, {
    required IconData icon,
    required String title,
    required String subtitle,
    required int bytes,
    String? action,
    Future<void> Function()? onAction,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(
        subtitle,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            formatBytes(bytes),
            style: theme.textTheme.bodyMedium?.copyWith(
              fontFeatures: const [],
            ),
          ),
          if (action != null) ...[
            const SizedBox(width: 4),
            TextButton(onPressed: onAction, child: Text(action)),
          ],
        ],
      ),
    );
  }

  /// 清空图片缓存：删除 imgcache 目录下全部文件（含 .meta sidecar），
  /// 目录本身保留。清理后回内存缓存仍在的图继续显示，下次进文重新下载。
  Future<void> _clearImageCache() async {
    final ok = await _confirm(
      context,
      title: '清理图片缓存',
      message: '删除所有缓存的网络图片（${formatBytes(_imgCacheBytes)}）？'
          '之后查看含图文章时会重新下载。',
      confirmText: '清理',
    );
    if (!ok) return;
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(
      '${docs.path}${Platform.pathSeparator}imgcache',
    );
    try {
      if (dir.existsSync()) {
        for (final e in dir.listSync(followLinks: false)) {
          try {
            if (e is File) {
              e.deleteSync();
            } else if (e is Directory) {
              e.deleteSync(recursive: true);
            }
          } on Object {
            // 单个文件删不掉（占用/权限）不阻断整体清理
          }
        }
      }
    } on Object {
      // 目录不可读时同样按"清完"处理，重新加载会显示真实剩余
    }
    await _load();
  }

  /// 清空所有仓库的阅读历史（复用清空阅读历史的实现，会刷新元数据体积）。
  Future<void> _clearHistory(BuildContext context) async {
    final ok = await _confirm(
      context,
      title: '清空阅读历史',
      message: '确定清空所有「最近阅读」记录吗？此操作不可撤销。',
      confirmText: '清空',
    );
    if (!ok) return;
    RepoMeta.clearRecents(_reposRoot);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已清空')),
    );
    await _load();
  }

  Future<bool> _confirm(
    BuildContext context, {
    required String title,
    required String message,
    required String confirmText,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(confirmText),
          ),
        ],
      ),
    );
    return ok ?? false;
  }
}
