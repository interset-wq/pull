import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

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
}
