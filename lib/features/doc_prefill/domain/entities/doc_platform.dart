/// 支持的文档平台枚举
enum DocPlatform { tencent, feishu, kdocs, unknown }

extension DocPlatformLabel on DocPlatform {
  String get displayName {
    switch (this) {
      case DocPlatform.tencent:
        return '微信 / 腾讯文档';
      case DocPlatform.feishu:
        return '飞书文档 / 多维表格';
      case DocPlatform.kdocs:
        return '金山文档 / WPS';
      case DocPlatform.unknown:
        return '未知平台';
    }
  }
}

/// 统一表单字段模型（屏蔽各平台字段结构差异）
class UnifiedDocField {
  final String fieldId;
  final String label;
  final String type; // text | number | date | phone | email
  final bool required;

  const UnifiedDocField({
    required this.fieldId,
    required this.label,
    required this.type,
    this.required = false,
  });
}

enum SubmitStatus { submitted, readyForReview, needsUserInput, failed }

class SubmitResult {
  final SubmitStatus status;
  final Map<String, dynamic> prefilledData;
  final List<String> missingFields;
  final String? message;

  const SubmitResult({
    required this.status,
    this.prefilledData = const {},
    this.missingFields = const [],
    this.message,
  });
}
