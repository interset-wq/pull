import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../git/repo_meta.dart';
import '../platforms/git_platform.dart';
import '../theme/app_prefs.dart';
import 'code_font.dart' show kCodeFontConsolas, kCodeFontJetBrains;

/// 应用发布页（GitCode Releases），供手动下载最新 APK 更新。
const String kReleaseUrl = 'https://gitcode.com/interset-wq/reader/releases';

/// 设置页：克隆偏好（默认托管平台 + 默认用户名）、
/// 代码字体选择与应用更新入口。
class SettingsPage extends StatelessWidget {
  const SettingsPage({required this.prefs, super.key});

  final AppPrefs prefs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('克隆', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          AnimatedBuilder(
            animation: prefs,
            builder: (context, _) => SegmentedButton<GitPlatform>(
              segments: [
                for (final p in GitPlatform.values)
                  ButtonSegment(value: p, label: Text(p.displayName)),
              ],
              selected: {prefs.platform},
              onSelectionChanged: (s) => prefs.setPlatform(s.first),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '输入 `用户名/仓库名` 或仅仓库名时，'
            '将按 ${prefs.platform.displayName} 与下方用户名自动拼接完整地址',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          AnimatedBuilder(
            animation: prefs,
            builder: (context, _) => TextFormField(
              initialValue: prefs.defaultOwner,
              decoration: InputDecoration(
                labelText: '默认用户名',
                hintText: '例如 interset-wq',
                border: const OutlineInputBorder(),
                helperText:
                    '克隆时只需输入仓库名，自动拼成 ${prefs.platform.webBase}/${prefs.defaultOwner.isEmpty ? '<用户名>' : prefs.defaultOwner}/<仓库>',
              ),
              onChanged: prefs.setDefaultOwner,
            ),
          ),
          const SizedBox(height: 32),
          Text('代码字体', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          AnimatedBuilder(
            animation: prefs,
            builder: (context, _) => SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: kCodeFontJetBrains,
                  label: Text('JetBrains Mono'),
                ),
                ButtonSegment(
                  value: kCodeFontConsolas,
                  label: Text('Consolas'),
                ),
              ],
              selected: {prefs.codeFont},
              onSelectionChanged: (s) => prefs.setCodeFont(s.first),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Consolas 为 Windows（VS Code）系统字体；'
            '移动端缺失时自动回退到内置的 JetBrains Mono',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 32),
          Text('阅读', style: theme.textTheme.titleMedium),
          AnimatedBuilder(
            animation: prefs,
            builder: (context, _) => SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.screen_lock_portrait_outlined),
              title: const Text('屏幕常亮'),
              subtitle: const Text('阅读文章时屏幕不会自动熄灭'),
              value: prefs.keepScreenOn,
              onChanged: (v) => prefs.setKeepScreenOn(v),
            ),
          ),
          AnimatedBuilder(
            animation: prefs,
            builder: (context, _) => SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.format_list_numbered_outlined),
              title: const Text('代码行号'),
              subtitle: const Text('代码块左侧显示行号列'),
              value: prefs.codeLineNumbers,
              onChanged: (v) => prefs.setCodeLineNumbers(v),
            ),
          ),
          AnimatedBuilder(
            animation: prefs,
            builder: (context, _) => SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.unfold_more_outlined),
              title: const Text('长代码块折叠'),
              subtitle: const Text('超过阈值的代码块默认收起，点击展开'),
              value: prefs.codeFoldEnabled,
              onChanged: (v) => prefs.setCodeFoldEnabled(v),
            ),
          ),
          AnimatedBuilder(
            animation: prefs,
            builder: (context, _) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.unfold_more_outlined),
              title: const Text('代码折叠阈值'),
              subtitle: Text('超过 ${prefs.codeFoldThreshold} 行的代码块默认折叠'),
              trailing: SizedBox(
                width: 140,
                child: Slider(
                  value: prefs.codeFoldThreshold.toDouble(),
                  min: 10,
                  max: 200,
                  divisions: 19, // 10 步进
                  label: '${prefs.codeFoldThreshold}',
                  onChanged: (v) =>
                      prefs.setCodeFoldThreshold(v.round()),
                ),
              ),
            ),
          ),
          AnimatedBuilder(
            animation: prefs,
            builder: (context, _) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.history),
              title: const Text('历史长度'),
              subtitle: Text('首页「最近阅读」最多保留 ${prefs.recentsLimit} 条'),
              trailing: SizedBox(
                width: 140,
                child: Slider(
                  value: prefs.recentsLimit.toDouble(),
                  min: 1,
                  max: 20,
                  divisions: 19,
                  label: '${prefs.recentsLimit}',
                  onChanged: (v) => prefs.setRecentsLimit(v.round()),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('数据', style: theme.textTheme.titleMedium),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.history_toggle_off),
            title: const Text('清空阅读历史'),
            subtitle: const Text('删除所有「最近阅读」记录'),
            trailing: const Icon(Icons.chevron_right, size: 18),
            onTap: () => _confirmClear(
              context,
              title: '清空阅读历史',
              message: '确定清空所有「最近阅读」记录吗？此操作不可撤销。',
              onConfirm: () {
                _clearData(context, clear: (root) => RepoMeta.clearRecents(root));
              },
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.star_outline),
            title: const Text('清空收藏'),
            subtitle: const Text('删除所有仓库中的收藏文章'),
            trailing: const Icon(Icons.chevron_right, size: 18),
            onTap: () => _confirmClear(
              context,
              title: '清空收藏',
              message: '确定清空所有仓库的收藏文章吗？此操作不可撤销。',
              onConfirm: () {
                _clearData(context, clear: (root) => RepoMeta.clearAllStars(root));
              },
            ),
          ),
          const SizedBox(height: 16),
          Text('应用', style: theme.textTheme.titleMedium),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.system_update_outlined),
            title: const Text('检查更新'),
            subtitle: const Text('前往 GitCode Releases 下载最新 APK'),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: () => launchUrl(
              Uri.parse(kReleaseUrl),
              mode: LaunchMode.externalApplication,
            ),
          ),
        ],
      ),
    );
  }

  /// 清空类操作统一走二次确认对话框。
  Future<void> _confirmClear(
    BuildContext context, {
    required String title,
    required String message,
    required VoidCallback onConfirm,
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
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (ok ?? false) onConfirm();
  }

  /// 在应用文档目录的 repos 根执行清空，并给出结果反馈。
  Future<void> _clearData(
    BuildContext context, {
    required void Function(String reposRoot) clear,
  }) async {
    final docs = await getApplicationDocumentsDirectory();
    final root = '${docs.path}${Platform.pathSeparator}repos';
    clear(root);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已清空')),
    );
  }
}
