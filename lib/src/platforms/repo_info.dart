import 'git_platform.dart';

/// 平台侧的仓库元信息（不含本地数据）。
///
/// 不再携带 `defaultBranch`：克隆直接检出远端 HEAD，调用方无需猜分支
/// （见 `GitSyncService.clone`）。
class RepoInfo {
  const RepoInfo({
    required this.platform,
    required this.owner,
    required this.name,
    required this.cloneUrl,
    this.isPrivate = false,
    this.description,
  });

  final GitPlatform platform;
  final String owner;
  final String name;
  final String cloneUrl;
  final bool isPrivate;
  final String? description;

  String get fullName => '$owner/$name';
}
