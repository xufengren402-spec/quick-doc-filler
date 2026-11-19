import 'package:quick_doc_filler/features/doc_prefill/domain/entities/doc_platform.dart';

/// 多平台文档统一适配器接口
abstract class DocPlatformAdapter {
  DocPlatform get platform;

  /// 解析文档链接并拉取表单字段结构
  Future<List<UnifiedDocField>> fetchFields(String docUrl);

  /// 将预填充并经用户确认的数据提交回原平台
  Future<bool> submitRecord(String docUrl, Map<String, dynamic> payload);
}
