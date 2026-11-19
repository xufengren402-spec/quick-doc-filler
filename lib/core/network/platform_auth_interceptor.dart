import 'package:dio/dio.dart';
import 'package:quick_doc_filler/core/network/oauth_manager.dart';
import 'package:quick_doc_filler/core/storage/secure_token_store.dart';
import 'package:quick_doc_filler/features/doc_prefill/domain/entities/doc_platform.dart';

/// 针对指定文档平台的 Dio 自动鉴权与 401 静默刷新拦截器
/// 继承 QueuedInterceptor，保证并发 401 时只执行一次 refresh，其余请求安全排队
class PlatformAuthInterceptor extends QueuedInterceptor {
  final DocPlatform platform;
  final String clientId;
  final SecureTokenStore tokenStore;
  final OAuthManager oauthManager;
  final Dio retryDio;

  PlatformAuthInterceptor({
    required this.platform,
    required this.clientId,
    required this.tokenStore,
    required this.oauthManager,
    required this.retryDio,
  });

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    var bundle = await tokenStore.read(platform);

    if (bundle != null && bundle.isExpiredOrExpiringSoon) {
      try {
        bundle = await oauthManager.refresh(platform);
      } catch (_) {
        // 预检刷新失败时放行，由 401 统一处理
      }
    }

    if (bundle != null) {
      _attachPlatformHeaders(options, bundle);
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final statusCode = err.response?.statusCode;
    final alreadyRetried = err.requestOptions.extra['_auth_retried'] == true;

    if (statusCode != 401 || alreadyRetried) {
      return handler.next(err);
    }

    try {
      var latest = await tokenStore.read(platform);
      final usedToken = _extractUsedToken(err.requestOptions);
      if (latest == null || latest.accessToken == usedToken) {
        latest = await oauthManager.refresh(platform);
      }

      final retriedOptions = err.requestOptions..extra['_auth_retried'] = true;
      _attachPlatformHeaders(retriedOptions, latest);

      final response = await retryDio.fetch(retriedOptions);
      return handler.resolve(response);
    } catch (_) {
      return handler.next(err);
    }
  }

  void _attachPlatformHeaders(RequestOptions options, OAuthTokenBundle bundle) {
    if (platform == DocPlatform.tencent) {
      options.headers['Client-Id'] = clientId;
      if (bundle.openId != null) {
        options.headers['Open-Id'] = bundle.openId;
      }
      options.headers['Access-Token'] = bundle.accessToken;
    } else {
      options.headers['Authorization'] = 'Bearer ${bundle.accessToken}';
    }
  }

  String? _extractUsedToken(RequestOptions options) {
    if (platform == DocPlatform.tencent) {
      return options.headers['Access-Token']?.toString();
    }
    final auth = options.headers['Authorization']?.toString() ?? '';
    return auth.startsWith('Bearer ') ? auth.substring(7) : null;
  }
}
