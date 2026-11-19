import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:quick_doc_filler/features/doc_prefill/domain/adapters/doc_platform_adapter.dart';
import 'package:quick_doc_filler/features/doc_prefill/domain/adapters/doc_platform_router.dart';
import 'package:quick_doc_filler/features/doc_prefill/domain/entities/doc_platform.dart';

class MockTencentAdapter extends Mock implements DocPlatformAdapter {}
class MockFeishuAdapter extends Mock implements DocPlatformAdapter {}
class MockKDocsAdapter extends Mock implements DocPlatformAdapter {}

void main() {
  late MockTencentAdapter tencentAdapter;
  late MockFeishuAdapter feishuAdapter;
  late MockKDocsAdapter kdocsAdapter;
  late DocPlatformRouter router;

  setUp(() {
    tencentAdapter = MockTencentAdapter();
    feishuAdapter = MockFeishuAdapter();
    kdocsAdapter = MockKDocsAdapter();

    when(() => tencentAdapter.platform).thenReturn(DocPlatform.tencent);
    when(() => feishuAdapter.platform).thenReturn(DocPlatform.feishu);
    when(() => kdocsAdapter.platform).thenReturn(DocPlatform.kdocs);

    router = DocPlatformRouter([tencentAdapter, feishuAdapter, kdocsAdapter]);
  });

  group('DocPlatformRouter 多平台识别测试', () {
    test('能够准确识别腾讯文档链接并路由到 TencentAdapter', () {
      const url = 'https://docs.qq.com/form/page/DWE5xExample';
      expect(router.detectPlatform(url), DocPlatform.tencent);
      expect(router.resolve(url), same(tencentAdapter));
    });

    test('能够识别飞书国内版与国际版（larksuite）链接', () {
      expect(
        router.detectPlatform('https://myorg.feishu.cn/base/app123'),
        DocPlatform.feishu,
      );
      expect(
        router.resolve('https://team.larksuite.com/docx/doc456'),
        same(feishuAdapter),
      );
    });

    test('能够识别金山文档（kdocs）与 WPS 域名链接', () {
      expect(
        router.resolve('https://www.kdocs.cn/l/c123456'),
        same(kdocsAdapter),
      );
      expect(
        router.detectPlatform('https://f.wps.cn/g/form789'),
        DocPlatform.kdocs,
      );
    });

    test('遇到未知域名或非法 URL 时抛出 UnsupportedError', () {
      expect(
        () => router.resolve('https://unknown-doc.example.com/123'),
        throwsA(isA<UnsupportedError>()),
      );
      expect(router.detectPlatform('not_a_valid_url'), DocPlatform.unknown);
    });
  });
}
