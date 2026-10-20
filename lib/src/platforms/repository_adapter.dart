import 'repo_info.dart';

/// 平台适配层统一接口：所有平台的 REST API 调用都经由它抽象，
/// 业务代码禁止直接写某家平台的 API。
abstract class RepositoryAdapter {
  /// 校验 token 是否有效，无效时抛出 [AdapterException]。
  Future<void> validateToken(String token);

  /// 列出 token 用户有权限读取的仓库。
  Future<List<RepoInfo>> listRepos(String token);

  /// 获取单个仓库信息。
  Future<RepoInfo> getRepo(String owner, String name, String token);
}

class AdapterException implements Exception {
  const AdapterException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() =>
      'AdapterException(${statusCode ?? 'no status'}): $message';
}
