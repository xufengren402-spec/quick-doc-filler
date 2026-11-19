import 'package:quick_doc_filler/features/doc_prefill/domain/adapters/doc_platform_adapter.dart';
import 'package:quick_doc_filler/features/doc_prefill/domain/entities/doc_platform.dart';

/// 演示与本地联调用三平台适配器（未配置企业 OpenAPI Token 时自动降级展示标准表单字段）
class DemoAwarePlatformAdapter implements DocPlatformAdapter {
  @override
  final DocPlatform platform;

  DemoAwarePlatformAdapter(this.platform);

  @override
  Future<List<UnifiedDocField>> fetchFields(String docUrl) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    switch (platform) {
      case DocPlatform.tencent:
        return const [
          UnifiedDocField(fieldId: 'q_name', label: '您的姓名', type: 'text', required: true),
          UnifiedDocField(fieldId: 'q_phone', label: '手机号码', type: 'phone', required: true),
          UnifiedDocField(fieldId: 'q_dept', label: '所属部门/学院', type: 'text', required: true),
          UnifiedDocField(fieldId: 'q_note', label: '备注说明', type: 'text', required: false),
        ];
      case DocPlatform.feishu:
        return const [
          UnifiedDocField(fieldId: '姓名', label: '姓名', type: 'text', required: true),
          UnifiedDocField(fieldId: '联系电话', label: '联系电话', type: 'phone', required: true),
          UnifiedDocField(fieldId: '工作邮箱', label: '工作邮箱', type: 'email', required: true),
          UnifiedDocField(fieldId: '所属部门', label: '所属部门', type: 'text', required: false),
        ];
      case DocPlatform.kdocs:
        return const [
          UnifiedDocField(fieldId: 'k_name', label: '填报人姓名', type: 'text', required: true),
          UnifiedDocField(fieldId: 'k_phone', label: '联系方式', type: 'phone', required: true),
          UnifiedDocField(fieldId: 'k_email', label: '电子邮箱', type: 'email', required: false),
        ];
      case DocPlatform.unknown:
        throw UnsupportedError('未知文档平台');
    }
  }

  @override
  Future<bool> submitRecord(String docUrl, Map<String, dynamic> payload) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    return payload.isNotEmpty;
  }
}
