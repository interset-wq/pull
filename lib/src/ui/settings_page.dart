import 'package:flutter/material.dart';

import '../platforms/git_platform.dart';
import '../theme/app_prefs.dart';

/// 设置页：克隆偏好（默认托管平台 + 默认用户名），
/// 供克隆对话框用 `repo` / `owner/repo` 短输入自动拼接完整 URL。
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
        ],
      ),
    );
  }
}
