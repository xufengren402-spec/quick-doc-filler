import 'package:dio/dio.dart';
import 'package:quick_doc_filler/core/storage/secure_token_store.dart';
import 'package:quick_doc_filler/features/doc_prefill/domain/entities/doc_platform.dart';

/// 单个平台的 OAuth2 配置项
class OAuthPlatformConfig {
  final String clientId;
  final String redirectUrl;
  final String tokenEndpoint;

  const OAuthPlatformConfig({
    required this.clientId,
    required this.redirectUrl,
    required this.tokenEndpoint,
  });
}

/// 三平台统一 OAuth2 刷新管理接口
class OAuthManager {
  final Dio _dio;
  final SecureTokenStore _tokenStore;
  final Map<DocPlatform, OAuthPlatformConfig> _configs;

  OAuthManager({
    Dio? dio,
    required SecureTokenStore tokenStore,
    required Map<DocPlatform, OAuthPlatformConfig> configs,
  })  : _dio = dio ?? Dio(),
        _tokenStore = tokenStore,
        _configs = configs;

  /// 使用 refresh_token 静默刷新凭据
  Future<OAuthTokenBundle> refresh(DocPlatform platform) async {
    final config = _configs[platform];
    if (config == null) {
      throw ArgumentError('未配置平台 ${platform.name} 的 OAuth 参数');
    }
    final current = await _tokenStore.read(platform);
    if (current?.refreshToken == null) {
      await _tokenStore.clear(platform);
      throw StateError('${platform.name} 登录已过期，请重新授权');
    }

    try {
      final res = await _dio.post(
        config.tokenEndpoint,
        data: {
          'grant_type': 'refresh_token',
          'client_id': config.clientId,
          'refresh_token': current!.refreshToken,
        },
      );
      final data = res.data as Map<String, dynamic>;
      final accessToken = data['access_token']?.toString();
      if (accessToken == null || accessToken.isEmpty) {
        throw StateError('刷新接口未返回 access_token');
      }
      final expiresIn = (data['expires_in'] as num?)?.toInt() ?? 7200;
      final updated = OAuthTokenBundle(
        accessToken: accessToken,
        refreshToken: data['refresh_token']?.toString() ?? current.refreshToken,
        openId: data['open_id']?.toString() ?? current.openId,
        expiresAt: DateTime.now().add(Duration(seconds: expiresIn)),
      );
      await _tokenStore.save(platform, updated);
      return updated;
    } catch (_) {
      await _tokenStore.clear(platform);
      rethrow;
    }
  }
}
