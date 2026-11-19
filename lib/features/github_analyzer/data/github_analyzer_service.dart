import 'package:dio/dio.dart';

/// GitHub 项目质量评估报告模型
class RepoQualityReport {
  final String fullName;
  final String description;
  final String htmlUrl;
  final int stars;
  final int contributorsCount;
  final DateTime updatedAt;
  final String qualityGrade; // A / B / C
  final String evaluationSummary;

  const RepoQualityReport({
    required this.fullName,
    required this.description,
    required this.htmlUrl,
    required this.stars,
    required this.contributorsCount,
    required this.updatedAt,
    required this.qualityGrade,
    required this.evaluationSummary,
  });
}

/// 基于官方 GitHub REST API 的项目搜索与质量评估服务
class GitHubAnalyzerService {
  final Dio _dio;

  GitHubAnalyzerService({String? githubToken})
      : _dio = Dio(
          BaseOptions(
            baseUrl: 'https://api.github.com',
            connectTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(seconds: 15),
            headers: {
              'Accept': 'application/vnd.github+json',
              if (githubToken != null && githubToken.isNotEmpty)
                'Authorization': 'Bearer $githubToken',
            },
          ),
        );

  /// 便于单元测试注入 MockDio
  GitHubAnalyzerService.withDio(this._dio);

  Future<List<RepoQualityReport>> searchAndEvaluate({
    required String keyword,
    String language = 'dart',
    int minStars = 100,
    int limit = 5,
  }) async {
    try {
      final query = '$keyword language:$language stars:>=$minStars';
      final response = await _dio.get(
        '/search/repositories',
        queryParameters: {
          'q': query,
          'sort': 'stars',
          'order': 'desc',
          'per_page': limit,
        },
      );

      final items = response.data is Map ? response.data['items'] : null;
      if (items is! List) {
        throw const FormatException('GitHub API 返回结构异常：缺少 items 列表');
      }

      final List<RepoQualityReport> reports = [];
      for (final item in items) {
        final map = item as Map<String, dynamic>;
        final fullName = map['full_name'] as String? ?? 'unknown';
        final stars = map['stargazers_count'] as int? ?? 0;
        final updatedAt =
            DateTime.tryParse(map['updated_at']?.toString() ?? '') ??
                DateTime(1970);

        final contributorsCount = await _fetchContributorsCount(fullName);

        reports.add(
          _evaluateRepo(
            fullName: fullName,
            description: map['description']?.toString() ?? '暂无项目简介',
            htmlUrl: map['html_url']?.toString() ?? '',
            stars: stars,
            contributorsCount: contributorsCount,
            updatedAt: updatedAt,
          ),
        );
      }
      return reports;
    } on DioException catch (e) {
      final statusCode = e.response?.statusCode;
      if (statusCode == 403 || statusCode == 429) {
        throw Exception('触发 GitHub API 速率限制（HTTP $statusCode），请配置 Token 或稍后重试。');
      } else if (statusCode == 401) {
        throw Exception('GitHub Token 无效或已过期，请检查配置。');
      } else if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout) {
        throw Exception('连接 GitHub API 超时，请检查网络环境。');
      }
      throw Exception('GitHub API 请求失败：${e.message}');
    } on FormatException catch (e) {
      throw Exception('数据解析错误：${e.message}');
    }
  }

  Future<int> _fetchContributorsCount(String fullName) async {
    try {
      final res = await _dio.get(
        '/repos/$fullName/contributors',
        queryParameters: {'per_page': 30, 'anon': 'false'},
      );
      return (res.data is List) ? (res.data as List).length : 0;
    } catch (_) {
      return 0;
    }
  }

  RepoQualityReport _evaluateRepo({
    required String fullName,
    required String description,
    required String htmlUrl,
    required int stars,
    required int contributorsCount,
    required DateTime updatedAt,
  }) {
    final daysSinceUpdate = DateTime.now().difference(updatedAt).inDays;
    final bool isActive = daysSinceUpdate <= 180;

    String grade = 'C';
    String summary = '社区规模较小或维护停滞，整合前需充分审查源码。';

    if (stars >= 1000 && contributorsCount >= 10 && isActive) {
      grade = 'A';
      summary = '高星标且近半年持续维护，社区协作健康，适合直接作为核心组件整合。';
    } else if (stars >= 200 && contributorsCount >= 3 && isActive) {
      grade = 'B';
      summary = '具备一定成熟度且保持更新，可参考其实现逻辑或做轻度二次封装。';
    }

    return RepoQualityReport(
      fullName: fullName,
      description: description,
      htmlUrl: htmlUrl,
      stars: stars,
      contributorsCount: contributorsCount,
      updatedAt: updatedAt,
      qualityGrade: grade,
      evaluationSummary: summary,
    );
  }
}
