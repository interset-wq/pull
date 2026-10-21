import 'dart:convert';

import 'package:http/http.dart' as http;

import 'git_platform.dart';
import 'repo_info.dart';
import 'repository_adapter.dart';

/// GitHub REST API v3 适配器（仅公开仓库，无需凭据）。
class GitHubAdapter implements RepositoryAdapter {
  GitHubAdapter({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Map<String, String> get _headers =>
      {'Accept': 'application/vnd.github+json'};

  @override
  Future<RepoInfo> getRepo(String owner, String name) async {
    final res = await _client.get(
      Uri.parse('${GitPlatform.github.apiBase}/repos/$owner/$name'),
      headers: _headers,
    );
    _check(res.statusCode, '获取 GitHub 仓库 $owner/$name 失败');
    return _fromRepo(
      jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>,
    );
  }

  RepoInfo _fromRepo(Map<String, dynamic> json) => RepoInfo(
        platform: GitPlatform.github,
        owner: (json['owner'] as Map<String, dynamic>)['login'] as String,
        name: json['name'] as String,
        cloneUrl: json['clone_url'] as String,
        defaultBranch: (json['default_branch'] ?? 'main') as String,
        isPrivate: json['private'] as bool? ?? false,
        description: json['description'] as String?,
      );

  void _check(int statusCode, String message) {
    if (statusCode != 200) {
      throw AdapterException(message, statusCode: statusCode);
    }
  }
}
