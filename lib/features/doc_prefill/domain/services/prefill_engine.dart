import 'package:quick_doc_filler/core/storage/secure_token_store.dart';
import 'package:quick_doc_filler/features/doc_prefill/domain/adapters/doc_platform_adapter.dart';
import 'package:quick_doc_filler/features/doc_prefill/domain/entities/doc_platform.dart';

/// 预填充与字段校验核心引擎
class PrefillEngine {
  final DocPlatformAdapter adapter;
  final UserProfileStore profileStore;

  PrefillEngine({required this.adapter, required this.profileStore});

  Future<SubmitResult> execute({
    required String docUrl,
    bool autoSubmit = false,
  }) async {
    final fields = await adapter.fetchFields(docUrl);
    final profile = await profileStore.getDecryptedProfile();

    final Map<String, dynamic> filled = {};
    final List<String> missing = [];

    for (final field in fields) {
      final matched = matchValueByRule(field.label, profile);
      if (matched != null && validateField(field, matched)) {
        filled[field.fieldId] = matched;
      } else if (field.required) {
        missing.add(field.label);
      }
    }

    if (missing.isNotEmpty) {
      return SubmitResult(
        status: SubmitStatus.needsUserInput,
        prefilledData: filled,
        missingFields: missing,
        message: '缺少或格式不正确的必填项：${missing.join("、")}',
      );
    }

    if (!autoSubmit) {
      return SubmitResult(
        status: SubmitStatus.readyForReview,
        prefilledData: filled,
      );
    }

    final ok = await adapter.submitRecord(docUrl, filled);
    return SubmitResult(
      status: ok ? SubmitStatus.submitted : SubmitStatus.failed,
      prefilledData: filled,
      message: ok ? '提交成功' : '提交失败，请检查授权或网络状态',
    );
  }

  /// 字段语义同义词匹配规则
  dynamic matchValueByRule(String label, Map<String, dynamic> profile) {
    final normalized = label.toLowerCase();
    if (normalized.contains('手机') ||
        normalized.contains('电话') ||
        normalized.contains('联系') ||
        normalized.contains('tel')) {
      return profile['phone'];
    }
    if (normalized.contains('姓名') || normalized.contains('名字') || normalized.contains('name')) {
      return profile['name'];
    }
    if (normalized.contains('邮箱') || normalized.contains('email') || normalized.contains('mail')) {
      return profile['email'];
    }
    if (normalized.contains('部门') || normalized.contains('单位') || normalized.contains('学院')) {
      return profile['department'];
    }
    return profile[label];
  }

  /// 基础格式校验
  bool validateField(UnifiedDocField field, dynamic value) {
    if (value == null || value.toString().trim().isEmpty) return false;
    final text = value.toString().trim();
    if (field.type == 'phone') {
      return RegExp(r'^1[3-9]\d{9}$').hasMatch(text);
    }
    if (field.type == 'email') {
      return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(text);
    }
    return true;
  }
}
