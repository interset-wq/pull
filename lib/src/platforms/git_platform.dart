/// 支持的 git 托管平台。
enum GitPlatform {
  github('GitHub', 'https://api.github.com'),
  gitee('Gitee', 'https://gitee.com/api/v5'),
  gitcode('GitCode', 'https://gitcode.com/api/v5');

  const GitPlatform(this.displayName, this.apiBase);

  final String displayName;
  final String apiBase;
}
