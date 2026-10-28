import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../git/repo_meta.dart';
import '../platforms/git_platform.dart';
import '../theme/app_prefs.dart';
import 'code_font.dart' show kCodeFontConsolas, kCodeFontJetBrains;

/// 应用发布页（GitHub Releases，CI 自动构建发布），供手动下载最新 APK。
const String kReleaseUrl = 'https://github.com/interset-wq/pullread/releases';

/// 应用图标选项（与 AppPrefs.kAppIconKeys / AndroidManifest alias 对应）。
const Map<String, String> kAppIconLabels = {
  'book': '摊开书',
  'page': '页即箭',
  'arrow': '抽页成箭',
  'converge': '汇页箭',
  'tray': '页堆箭',
};

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
          const SizedBox(height: 8),
          AnimatedBuilder(
            animation: prefs,
            builder: (context, _) => SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.sync_outlined),
              title: const Text('自动拉取同步'),
              subtitle: const Text(
                  '启动应用时后台静默 pull 所有仓库；默认关闭——下拉刷新或仓库页刷新按钮即可手动同步'),
              value: prefs.silentPull,
              onChanged: (v) => prefs.setSilentPull(v),
            ),
          ),
          const SizedBox(height: 8),
          AnimatedBuilder(
            animation: prefs,
            builder: (context, _) => SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.account_tree_outlined),
              title: const Text('目录树模式'),
              subtitle: const Text(
                  '仓库页目录就地展开/折叠，一页看全整个仓库；默认关闭——点目录逐级进入（类似文件资源管理器），指向目录的链接可正常跳转'),
              value: prefs.treeMode,
              onChanged: (v) => prefs.setTreeMode(v),
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
              secondary: const Icon(Icons.swipe_outlined),
              title: const Text('手势翻页'),
              subtitle: const Text('正文区左右快滑切换上一篇/下一篇'),
              value: prefs.swipePaging,
              onChanged: (v) => prefs.setSwipePaging(v),
            ),
          ),
          AnimatedBuilder(
            animation: prefs,
            builder: (context, _) => SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.table_rows_outlined),
              title: const Text('表格不换行'),
              subtitle: const Text(
                  '每个表格右上角有切换按钮：平铺（按内容自然宽度横向滚动，一行放下所有内容）或换行（限两倍屏宽均分列宽）。此开关决定默认档位；关闭时超宽表格自动换行'),
              value: prefs.wideTable,
              onChanged: (v) => prefs.setWideTable(v),
            ),
          ),
          AnimatedBuilder(
            animation: prefs,
            builder: (context, _) => SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.subject_outlined),
              title: const Text('折叠块默认展开'),
              subtitle: const Text(
                  'Markdown 折叠块（<details>）未显式 open 时的默认展开状态'),
              value: prefs.detailsExpanded,
              onChanged: (v) => prefs.setDetailsExpanded(v),
            ),
          ),
          AnimatedBuilder(
            animation: prefs,
            builder: (context, _) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.format_line_spacing_outlined),
              title: const Text('正文行距'),
              subtitle: Text('行高倍数 ${prefs.lineHeight.toStringAsFixed(2)}'),
              trailing: SizedBox(
                width: 140,
                child: Slider(
                  value: prefs.lineHeight,
                  min: 1.4,
                  max: 2.2,
                  divisions: 16, // 0.05 步进（默认 1.75 必须落在档位上）
                  label: prefs.lineHeight.toStringAsFixed(2),
                  onChanged: (v) => prefs.setLineHeight(v),
                ),
              ),
            ),
          ),
          AnimatedBuilder(
            animation: prefs,
            builder: (context, _) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.settings_overscan_outlined),
              title: const Text('页边距'),
              subtitle: Text('正文两侧留白 ${prefs.pageMargin.round()} dp'),
              trailing: SizedBox(
                width: 140,
                child: Slider(
                  value: prefs.pageMargin,
                  min: 8,
                  max: 32,
                  divisions: 12, // 2 dp 步进
                  label: '${prefs.pageMargin.round()}',
                  onChanged: (v) => prefs.setPageMargin(v),
                ),
              ),
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
          const SizedBox(height: 8),
          const SizedBox(height: 32),
          Text('应用图标', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          AnimatedBuilder(
            animation: prefs,
            builder: (context, _) => Row(
              children: [
                for (final e in kAppIconLabels.entries)
                  Expanded(
                    child: _IconOption(
                      label: e.value,
                      asset: 'assets/icons/icon_${e.key}.png',
                      selected: prefs.appIcon == e.key,
                      onTap: () => prefs.setAppIcon(e.key),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '切换后桌面图标在 launcher 刷新后生效（部分机型需重新启动桌面）',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
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
          AnimatedBuilder(
            animation: prefs,
            builder: (context, _) => SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.visibility_off_outlined),
              title: const Text('隐藏默认忽略项'),
              subtitle: const Text('点开头的文件/目录（.git 恒忽略）'),
              value: prefs.ignoreDefaults,
              onChanged: prefs.setIgnoreDefaults,
            ),
          ),
          AnimatedBuilder(
            animation: prefs,
            builder: (context, _) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.rule_outlined),
              title: const Text('自定义隐藏规则'),
              subtitle: Text(
                prefs.ignoreRules.isEmpty
                    ? '按文件/目录名精确匹配，跨仓库生效；未添加'
                    : '${prefs.ignoreRules.length} 条：${prefs.ignoreRules.join('、')}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: const Icon(Icons.chevron_right, size: 18),
              onTap: () => _editIgnoreRules(context),
            ),
          ),
          const SizedBox(height: 16),
          Text('应用', style: theme.textTheme.titleMedium),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.system_update_outlined),
            title: const Text('检查更新'),
            subtitle: const Text('前往 GitHub Releases 下载最新 APK'),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: () => launchUrl(
              Uri.parse(kReleaseUrl),
              mode: LaunchMode.externalApplication,
            ),
          ),
          const _AppInfoTile(),
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

  /// 编辑自定义隐藏规则：每行一条（文件/目录名精确匹配）。
  /// 「恢复默认」清空规则并把默认隐藏规则开关恢复为开。
  Future<void> _editIgnoreRules(BuildContext context) async {
    final controller = TextEditingController(
      text: prefs.ignoreRules.join('\n'),
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('自定义隐藏规则'),
        content: TextField(
          controller: controller,
          maxLines: 6,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '每行一条，例如：\ndist\nbuild\nassets',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              prefs.resetIgnoreRules();
              Navigator.pop(dialogContext, false);
            },
            child: const Text('恢复默认'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final rules = controller.text
        .split('\n')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();
    await prefs.setIgnoreRules(rules);
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

/// 「应用信息」入口：点击进入关于页，详细信息在关于页内加载。
class _AppInfoTile extends StatelessWidget {
  const _AppInfoTile();

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.info_outline),
      title: const Text('应用信息'),
      trailing: const Icon(Icons.chevron_right, size: 18),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const _AboutPage()),
      ),
    );
  }
}

/// 关于页（文件内私有）：采用应用商店流行的 About 形式——居中应用图标 + 名称 +
/// 版本号，下方分组列出包名、开源许可证、项目主页与检查更新入口。
class _AboutPage extends StatefulWidget {
  const _AboutPage();

  @override
  State<_AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<_AboutPage> {
  static const _channel = MethodChannel('app_icon');
  static const _repoUrl = 'https://github.com/interset-wq/pullread';
  static const _licenseUrl = '$_repoUrl/blob/main/LICENSE';

  Map<Object?, Object?>? _info;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      // MethodChannel 编解码返回 Map<Object?, Object?>，直接指定更具体的
      // 泛型会在 cast 处抛 TypeError，须按原始类型接收后自行取值
      final info = await _channel
          .invokeMethod<Map<Object?, Object?>>('getInfo')
          .timeout(const Duration(seconds: 3));
      if (mounted && info != null) setState(() => _info = info);
    } on Object {
      // Windows 预览 / 通道异常：仅显示静态信息
    }
  }

  Future<void> _open(Uri uri) async {
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } on Object {
      // 打不开（无浏览器等）静默忽略
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final version = _info == null
        ? null
        : '${_info!['versionName']}+${_info!['versionCode']}';
    return Scaffold(
      appBar: AppBar(title: const Text('关于')),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          const SizedBox(height: 40),
          Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: Image.asset(
                'assets/icons/icon_book.png',
                width: 96,
                height: 96,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              'PullRead 拉读',
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          if (version != null) ...[
            const SizedBox(height: 6),
            Center(
              child: Text(
                'v$version',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
          const SizedBox(height: 40),
          if (_info != null)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.tag_outlined),
              title: const Text('包名'),
              subtitle: Text('${_info!['packageName']}'),
            ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.history_edu_outlined),
            title: const Text('开源许可证'),
            subtitle: const Text('MIT License'),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: () => _open(Uri.parse(_licenseUrl)),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.code_outlined),
            title: const Text('项目主页'),
            subtitle: const Text('GitHub · interset-wq/pullread'),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: () => _open(Uri.parse(_repoUrl)),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.system_update_outlined),
            title: const Text('检查更新'),
            subtitle: const Text('下载最新 Release APK'),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: () => _open(Uri.parse(kReleaseUrl)),
          ),
          const SizedBox(height: 24),
          Center(
            child: Text(
              '把笔记仓库装进口袋的原生阅读器',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

/// 应用图标选项卡片：预览图 + 名称，选中态描边。
class _IconOption extends StatelessWidget {
  const _IconOption({
    required this.label,
    required this.asset,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String asset;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: selected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.outlineVariant,
                  width: selected ? 2 : 1,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.asset(asset, width: 56, height: 56),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: selected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
                fontWeight:
                    selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
