import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:quick_doc_filler/features/github_analyzer/data/github_analyzer_service.dart';

class MockDio extends Mock implements Dio {}

void main() {
  late MockDio mockDio;
  late GitHubAnalyzerService service;

  setUp(() {
    mockDio = MockDio();
    service = GitHubAnalyzerService.withDio(mockDio);
  });

  group('GitHubAnalyzerService 质量评估与异常处理测试', () {
    test('高星标、多贡献者且近期维护的项目应评定为 A 级', () async {
      final recentIso = DateTime.now().subtract(const Duration(days: 10)).toIso8601String();

      when(() => mockDio.get(
            '/search/repositories',
            queryParameters: any(named: 'queryParameters'),
          )).thenAnswer((_) async => Response(
            requestOptions: RequestOptions(path: '/search/repositories'),
            statusCode: 200,
            data: {
              'items': [
                {
                  'full_name': 'flutter-form-builder-ecosystem/flutter_form_builder',
                  'stargazers_count': 1600,
                  'updated_at': recentIso,
                },
              ],
            },
          ));

      when(() => mockDio.get(
            '/repos/flutter-form-builder-ecosystem/flutter_form_builder/contributors',
            queryParameters: any(named: 'queryParameters'),
          )).thenAnswer((_) async => Response(
            requestOptions: RequestOptions(path: '/contributors'),
            statusCode: 200,
            data: List.generate(15, (i) => {'login': 'dev_$i'}),
          ));

      final reports = await service.searchAndEvaluate(keyword: 'form_builder');

      expect(reports.length, 1);
      expect(reports.first.qualityGrade, 'A');
      expect(reports.first.stars, 1600);
      expect(reports.first.contributorsCount, 15);
    });

    test('触发 GitHub API 403 速率限制时应抛出明确的限流提示', () async {
      when(() => mockDio.get(
            '/search/repositories',
            queryParameters: any(named: 'queryParameters'),
          )).thenThrow(DioException(
        requestOptions: RequestOptions(path: '/search/repositories'),
        response: Response(
          requestOptions: RequestOptions(path: '/search/repositories'),
          statusCode: 403,
        ),
        type: DioExceptionType.badResponse,
      ));

      expect(
        () => service.searchAndEvaluate(keyword: 'flutter'),
        throwsA(predicate((e) => e.toString().contains('速率限制'))),
      );
    });

    test('API 响应缺少 items 字段时应抛出数据解析异常', () async {
      when(() => mockDio.get(
            '/search/repositories',
            queryParameters: any(named: 'queryParameters'),
          )).thenAnswer((_) async => Response(
            requestOptions: RequestOptions(path: '/search/repositories'),
            statusCode: 200,
            data: {'unexpected_key': []},
          ));

      expect(
        () => service.searchAndEvaluate(keyword: 'flutter'),
        throwsA(predicate((e) => e.toString().contains('数据解析错误'))),
      );
    });
  });
}
