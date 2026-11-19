import 'package:quick_doc_filler/features/doc_prefill/domain/adapters/doc_platform_adapter.dart';
import 'package:quick_doc_filler/features/doc_prefill/domain/entities/doc_platform.dart';

/// 文档平台路由器：根据 URL 自动分发到对应平台适配器
class DocPlatformRouter {
  final Map<DocPlatform, DocPlatformAdapter> _adapters;

  DocPlatformRouter(List<DocPlatformAdapter> adapters)
      : _adapters = {for (final a in adapters) a.platform: a};

  DocPlatform detectPlatform(String docUrl) {
    final host = Uri.tryParse(docUrl)?.host.toLowerCase() ?? '';
    if (host.contains('docs.qq.com')) return DocPlatform.tencent;
    if (host.contains('feishu.cn') || host.contains('larksuite.com')) {
      return DocPlatform.feishu;
    }
    if (host.contains('kdocs.cn') || host.contains('wps.cn')) {
      return DocPlatform.kdocs;
    }
    return DocPlatform.unknown;
  }

  DocPlatformAdapter resolve(String docUrl) {
    final platform = detectPlatform(docUrl);
    final adapter = _adapters[platform];
    if (adapter == null) {
      throw UnsupportedError('暂不支持该文档链接所属平台：$docUrl');
    }
    return adapter;
  }
}
