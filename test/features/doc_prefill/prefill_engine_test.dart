import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:quick_doc_filler/core/storage/secure_token_store.dart';
import 'package:quick_doc_filler/features/doc_prefill/domain/adapters/doc_platform_adapter.dart';
import 'package:quick_doc_filler/features/doc_prefill/domain/entities/doc_platform.dart';
import 'package:quick_doc_filler/features/doc_prefill/domain/services/prefill_engine.dart';

class MockDocAdapter extends Mock implements DocPlatformAdapter {}
class MockUserProfileStore extends Mock implements UserProfileStore {}

void main() {
  late MockDocAdapter adapter;
  late MockUserProfileStore profileStore;
  late PrefillEngine engine;

  setUp(() {
    adapter = MockDocAdapter();
    profileStore = MockUserProfileStore();
    engine = PrefillEngine(adapter: adapter, profileStore: profileStore);
  });

  group('PrefillEngine 预填充与自动提交测试', () {
    test('当所有必填字段匹配且格式合法时，autoSubmit=true 自动提交成功', () async {
      const docUrl = 'https://docs.qq.com/form/page/test01';
      when(() => adapter.fetchFields(docUrl)).thenAnswer((_) async => const [
            UnifiedDocField(fieldId: 'f_name', label: '您的姓名', type: 'text', required: true),
            UnifiedDocField(fieldId: 'f_phone', label: '联系电话', type: 'phone', required: true),
          ]);
      when(() => profileStore.getDecryptedProfile()).thenAnswer((_) async => {
            'name': '张明',
            'phone': '13800138000',
          });
      when(() => adapter.submitRecord(docUrl, any())).thenAnswer((_) async => true);

      final result = await engine.execute(docUrl: docUrl, autoSubmit: true);

      expect(result.status, SubmitStatus.submitted);
      verify(() => adapter.submitRecord(docUrl, {
            'f_name': '张明',
            'f_phone': '13800138000',
          })).called(1);
    });

    test('当必填手机号格式非法或缺失时，阻断自动提交并返回缺失字段列表', () async {
      const docUrl = 'https://myorg.feishu.cn/base/test02';
      when(() => adapter.fetchFields(docUrl)).thenAnswer((_) async => const [
            UnifiedDocField(fieldId: 'f_phone', label: '手机号码', type: 'phone', required: true),
            UnifiedDocField(fieldId: 'f_dept', label: '所属部门', type: 'text', required: true),
          ]);
      when(() => profileStore.getDecryptedProfile()).thenAnswer((_) async => {
            'phone': '12345',
          });

      final result = await engine.execute(docUrl: docUrl, autoSubmit: true);

      expect(result.status, SubmitStatus.needsUserInput);
      expect(result.missingFields, containsAll(['手机号码', '所属部门']));
      verifyNever(() => adapter.submitRecord(any(), any()));
    });
  });
}
