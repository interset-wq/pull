/// 支持的 git 托管平台。
enum GitPlatform {
  github('GitHub', 'https://api.github.com', 'https://github.com'),
  gitee('Gitee', 'https://gitee.com/api/v5', 'https://gitee.com'),
  gitcode('GitCode', 'https://gitcode.com/api/v5', 'https://gitcode.com'),
  atomgit('AtomGit', 'https://api.atomgit.com/api/v5', 'https://atomgit.com'),
  gitlab('GitLab', 'https://gitlab.com/api/v4', 'https://gitlab.com'),
  // 自建 Gitea/Gogs 等：没有可枚举的网页域名，只用于「来源展示 / 短名拼接」
  // 之外的兜底——克隆本身只依赖用户输入的完整 URL。
  other('其他', '', '');

  const GitPlatform(this.displayName, this.apiBase, this.webBase);

  final String displayName;
  final String apiBase;

  /// 网页域名：拼接 `owner/repo.git` 形式的克隆地址；未知平台为空串。
  final String webBase;
}

/// 按 URL 猜平台：识别不出时返回 [GitPlatform.other]。
///
/// 注意这只影响展示与「默认平台」提示，不参与克隆逻辑——克隆始终用
/// 用户给的完整 URL，因此自建 Gitea 等域名同样能克隆。
GitPlatform guessPlatform(String url) {
  final lower = url.toLowerCase();
  if (lower.contains('github.com')) return GitPlatform.github;
  if (lower.contains('gitee.com')) return GitPlatform.gitee;
  if (lower.contains('gitlab.com')) return GitPlatform.gitlab;
  if (lower.contains('atomgit.com')) return GitPlatform.atomgit;
  // gitcode.com 是 AtomGit 历史域名，两者均广泛使用，分别保留各自平台
  if (lower.contains('gitcode.com')) return GitPlatform.gitcode;
  return GitPlatform.other;
}
