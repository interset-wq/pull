import 'dart:convert';

import 'package:http/http.dart' as http;

import 'git_platform.dart';
import 'repo_info.dart';
import 'repository_adapter.dart';

/// Gitee API v5 适配器（仅公开仓库，无需凭据）。
class GiteeAdapter implements RepositoryAdapter {
  GiteeAdapter({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Map<String, String> _headers() => {'Accept': 'application/json'};

  Uri _uri(String path) => Uri.parse('${GitPlatform.gitee.apiBase}$path');

  @override
  Future<RepoInfo> getRepo(String owner, String name) async {
    final res = await _client.get(
      _uri('/repos/$owner/$name'),
      headers: _headers(),
    );
    _check(res.statusCode, '获取 Gitee 仓库 $owner/$name 失败');
    return _fromRepo(
      jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>,
    );
  }

  RepoInfo _fromRepo(Map<String, dynamic> json) => RepoInfo(
        platform: GitPlatform.gitee,
        owner: (json['owner'] as Map<String, dynamic>)['login'] as String,
        name: json['path'] as String,
        cloneUrl: (json['html_url'] as String?)?.endsWith('.git') == true
            ? json['html_url'] as String
            : '${json['html_url']}.git',
        defaultBranch: (json['default_branch'] ?? 'master') as String,
        isPrivate: json['private'] as bool? ?? json['visibility'] == 'private',
        description: json['description'] as String?,
      );

  void _check(int statusCode, String message) {
    if (statusCode != 200) {
      throw AdapterException(message, statusCode: statusCode);
    }
  }
}
