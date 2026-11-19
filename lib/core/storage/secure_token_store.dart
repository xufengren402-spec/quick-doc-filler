import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:quick_doc_filler/features/doc_prefill/domain/entities/doc_platform.dart';

/// 跨平台统一 OAuth 凭据模型
class OAuthTokenBundle {
  final String accessToken;
  final String? refreshToken;
  final String? openId; // 腾讯文档请求头三元组必需字段
  final DateTime expiresAt;

  const OAuthTokenBundle({
    required this.accessToken,
    this.refreshToken,
    this.openId,
    required this.expiresAt,
  });

  /// 提前 60 秒判定为即将过期
  bool get isExpiredOrExpiringSoon =>
      DateTime.now().isAfter(expiresAt.subtract(const Duration(seconds: 60)));

  Map<String, dynamic> toJson() => {
        'accessToken': accessToken,
        'refreshToken': refreshToken,
        'openId': openId,
        'expiresAt': expiresAt.toIso8601String(),
      };

  factory OAuthTokenBundle.fromJson(Map<String, dynamic> json) {
    return OAuthTokenBundle(
      accessToken: json['accessToken'] as String,
      refreshToken: json['refreshToken'] as String?,
      openId: json['openId'] as String?,
      expiresAt: DateTime.parse(json['expiresAt'] as String),
    );
  }
}

/// 三平台加密 Token 存储
class SecureTokenStore {
  final FlutterSecureStorage _storage;

  SecureTokenStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  String _keyFor(DocPlatform platform) => 'oauth_bundle_${platform.name}';

  Future<void> save(DocPlatform platform, OAuthTokenBundle bundle) async {
    await _storage.write(
      key: _keyFor(platform),
      value: jsonEncode(bundle.toJson()),
    );
  }

  Future<OAuthTokenBundle?> read(DocPlatform platform) async {
    final raw = await _storage.read(key: _keyFor(platform));
    if (raw == null || raw.isEmpty) return null;
    try {
      return OAuthTokenBundle.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      await clear(platform);
      return null;
    }
  }

  Future<void> clear(DocPlatform platform) async {
    await _storage.delete(key: _keyFor(platform));
  }
}

/// 本地个人预填充档案抽象接口
abstract class UserProfileStore {
  Future<Map<String, dynamic>> getDecryptedProfile();
  Future<void> saveProfile(Map<String, dynamic> profile);
}

/// 基于 flutter_secure_storage 的加密个人档案实现
class SecureUserProfileStore implements UserProfileStore {
  static const _profileKey = 'encrypted_user_profile_v1';
  final FlutterSecureStorage _storage;

  SecureUserProfileStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  @override
  Future<Map<String, dynamic>> getDecryptedProfile() async {
    final raw = await _storage.read(key: _profileKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return {};
    }
  }

  @override
  Future<void> saveProfile(Map<String, dynamic> profile) async {
    await _storage.write(key: _profileKey, value: jsonEncode(profile));
  }
}
