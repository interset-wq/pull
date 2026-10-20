import 'git_platform.dart';

/// 平台侧的仓库元信息（不含本地数据）。
class RepoInfo {
  const RepoInfo({
    required this.platform,
    required this.owner,
    required this.name,
    required this.cloneUrl,
    required this.defaultBranch,
    this.isPrivate = false,
    this.description,
  });

  final GitPlatform platform;
  final String owner;
  final String name;
  final String cloneUrl;
  final String defaultBranch;
  final bool isPrivate;
  final String? description;

  String get fullName => '$owner/$name';
}
