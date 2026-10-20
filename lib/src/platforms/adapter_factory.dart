import 'git_platform.dart';
import 'github_adapter.dart';
import 'gitcode_adapter.dart';
import 'gitee_adapter.dart';
import 'repository_adapter.dart';

/// 按平台返回对应的适配器实例。
RepositoryAdapter adapterFor(GitPlatform platform) => switch (platform) {
      GitPlatform.github => GitHubAdapter(),
      GitPlatform.gitee => GiteeAdapter(),
      GitPlatform.gitcode => GitCodeAdapter(),
    };
