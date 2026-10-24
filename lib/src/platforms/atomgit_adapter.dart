import 'dart:convert';

import 'package:http/http.dart' as http;

import 'git_platform.dart';
import 'repo_info.dart';
import 'repository_adapter.dart';

/// AtomGit API v5 适配器（与 GitCode 同源同风格，仅公开仓库，无需凭据）。
///
/// AtomGit（atomgit.com）是主域名，GitCode（gitcode.com）是其历史域名，
/// 两者 API 结构一致；字段读取上对两家返回做兼容兜底。
class AtomGitAdapter implements RepositoryAdapter {
  AtomGitAdapter({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Map<String, String> _headers() => {'Accept': 'application/json'};

  Uri _uri(String path) => Uri.parse('${GitPlatform.atomgit.apiBase}$path');

  @override
  Future<RepoInfo> getRepo(String owner, String name) async {
    final res = await _client.get(
      _uri('/repos/$owner/$name'),
      headers: _headers(),
    );
    _check(res.statusCode, '获取 AtomGit 仓库 $owner/$name 失败');
    return _fromRepo(
      jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>,
      fallbackOwner: owner,
      fallbackName: name,
    );
  }

  RepoInfo _fromRepo(
    Map<String, dynamic> json, {
    required String fallbackOwner,
    required String fallbackName,
  }) {
    final ownerJson = json['owner'];
    final htmlUrl = (json['html_url'] as String?) ??
        '${GitPlatform.atomgit.webBase}/$fallbackOwner/$fallbackName';
    return RepoInfo(
      platform: GitPlatform.atomgit,
      owner: ownerJson is Map<String, dynamic>
          ? (ownerJson['login'] ?? ownerJson['username'] ?? fallbackOwner)
              as String
          : fallbackOwner,
      name: (json['path'] ?? json['name'] ?? fallbackName) as String,
      cloneUrl: htmlUrl.endsWith('.git') ? htmlUrl : '$htmlUrl.git',
      defaultBranch: (json['default_branch'] ?? 'main') as String,
      isPrivate: json['private'] as bool? ?? json['visibility'] == 'private',
      description: json['description'] as String?,
    );
  }

  void _check(int statusCode, String message) {
    if (statusCode != 200) {
      throw AdapterException(message, statusCode: statusCode);
    }
  }
}
