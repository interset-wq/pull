/// 支持的 git 托管平台。
enum GitPlatform {
  github('GitHub', 'https://api.github.com', 'https://github.com'),
  gitee('Gitee', 'https://gitee.com/api/v5', 'https://gitee.com'),
  gitcode('GitCode', 'https://gitcode.com/api/v5', 'https://gitcode.com'),
  atomgit('AtomGit', 'https://api.atomgit.com/api/v5', 'https://atomgit.com');

  const GitPlatform(this.displayName, this.apiBase, this.webBase);

  final String displayName;
  final String apiBase;

  /// 网页域名：拼接 `owner/repo.git` 形式的克隆地址。
  final String webBase;
}
