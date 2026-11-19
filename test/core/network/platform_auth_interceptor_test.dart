import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:quick_doc_filler/core/network/oauth_manager.dart';
import 'package:quick_doc_filler/core/network/platform_auth_interceptor.dart';
import 'package:quick_doc_filler/core/storage/secure_token_store.dart';
import 'package:quick_doc_filler/features/doc_prefill/domain/entities/doc_platform.dart';

class MockOAuthManager extends Mock implements OAuthManager {}

class InMemoryTokenStore extends SecureTokenStore {
  final Map<DocPlatform, OAuthTokenBundle> _cache = {};

  @override
  Future<void> save(DocPlatform platform, OAuthTokenBundle bundle) async {
    _cache[platform] = bundle;
  }

  @override
  Future<OAuthTokenBundle?> read(DocPlatform platform) async => _cache[platform];

  @override
  Future<void> clear(DocPlatform platform) async => _cache.remove(platform);
}

class FakeHttpClientAdapter implements HttpClientAdapter {
  final Future<ResponseBody> Function(RequestOptions options) onFetch;
  FakeHttpClientAdapter(this.onFetch);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) =>
      onFetch(options);

  @override
  void close({bool force = false}) {}
}

ResponseBody _jsonResponse(int statusCode, Map<String, dynamic> body) {
  return ResponseBody.fromString(
    jsonEncode(body),
    statusCode,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
}

void main() {
  late InMemoryTokenStore tokenStore;
  late MockOAuthManager oauthManager;

  setUp(() {
    tokenStore = InMemoryTokenStore();
    oauthManager = MockOAuthManager();
  });

  group('PlatformAuthInterceptor 并发 401 防重复刷新测试', () {
    test('3 个并发请求同时触发 401 时，应只调用 1 次 refresh 且全部重放成功', () async {
      await tokenStore.save(
        DocPlatform.feishu,
        OAuthTokenBundle(
          accessToken: 'revoked_token',
          refreshToken: 'valid_refresh_token',
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
        ),
      );

      when(() => oauthManager.refresh(DocPlatform.feishu)).thenAnswer((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        final refreshed = OAuthTokenBundle(
          accessToken: 'new_token_after_401',
          refreshToken: 'valid_refresh_token_2',
          expiresAt: DateTime.now().add(const Duration(hours: 2)),
        );
        await tokenStore.save(DocPlatform.feishu, refreshed);
        return refreshed;
      });

      final adapter = FakeHttpClientAdapter((options) async {
        final auth = options.headers['Authorization']?.toString();
        if (auth == 'Bearer new_token_after_401') {
          return _jsonResponse(200, {'path': options.path, 'ok': true});
        }
        return _jsonResponse(401, {'error': 'token_expired'});
      });

      final retryDio = Dio()..httpClientAdapter = adapter;
      final dio = Dio()
        ..httpClientAdapter = adapter
        ..interceptors.add(
          PlatformAuthInterceptor(
            platform: DocPlatform.feishu,
            clientId: 'fs_app',
            tokenStore: tokenStore,
            oauthManager: oauthManager,
            retryDio: retryDio,
          ),
        );

      final responses = await Future.wait([
        dio.get('https://open.feishu.cn/api/req_1'),
        dio.get('https://open.feishu.cn/api/req_2'),
        dio.get('https://open.feishu.cn/api/req_3'),
      ]);

      expect(responses.every((r) => r.statusCode == 200), isTrue);
      verify(() => oauthManager.refresh(DocPlatform.feishu)).called(1);
    });
  });
}
