import 'repo_info.dart';

/// 平台适配层统一接口：所有平台的 REST API 调用都经由它抽象，
/// 业务代码禁止直接写某家平台的 API。
/// 仅支持公开仓库，不需要任何凭据。
abstract class RepositoryAdapter {
  /// 获取单个公开仓库信息。
  Future<RepoInfo> getRepo(String owner, String name);
}

class AdapterException implements Exception {
  const AdapterException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() =>
      'AdapterException(${statusCode ?? 'no status'}): $message';
}
