import 'package:flutter/material.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quick_doc_filler/core/storage/secure_token_store.dart';
import 'package:quick_doc_filler/features/doc_prefill/data/adapters/platform_adapters.dart';
import 'package:quick_doc_filler/features/doc_prefill/domain/adapters/doc_platform_router.dart';
import 'package:quick_doc_filler/features/doc_prefill/domain/entities/doc_platform.dart';
import 'package:quick_doc_filler/features/doc_prefill/domain/services/prefill_engine.dart';
import 'package:quick_doc_filler/features/github_analyzer/data/github_analyzer_service.dart';

void main() {
  runApp(const ProviderScope(child: QuickDocFillerApp()));
}

class QuickDocFillerApp extends StatelessWidget {
  const QuickDocFillerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '文档快填助手',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF1D4ED8),
        useMaterial3: true,
      ),
      home: const MainHomeShell(),
    );
  }
}

class MainHomeShell extends StatefulWidget {
  const MainHomeShell({super.key});

  @override
  State<MainHomeShell> createState() => _MainHomeShellState();
}

class _MainHomeShellState extends State<MainHomeShell> {
  int _tabIndex = 0;
  final _profileStore = SecureUserProfileStore();
  late final _router = DocPlatformRouter([
    DemoAwarePlatformAdapter(DocPlatform.tencent),
    DemoAwarePlatformAdapter(DocPlatform.feishu),
    DemoAwarePlatformAdapter(DocPlatform.kdocs),
  ]);

  @override
  Widget build(BuildContext context) {
    final pages = [
      DocPrefillTab(router: _router, profileStore: _profileStore),
      UserProfileTab(profileStore: _profileStore),
      const GitHubAnalyzerTab(),
    ];

    return Scaffold(
      body: IndexedStack(index: _tabIndex, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (idx) => setState(() => _tabIndex = idx),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.edit_document),
            label: '文档填报',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            label: '个人档案',
          ),
          NavigationDestination(
            icon: Icon(Icons.hub_outlined),
            label: 'GitHub分析',
          ),
        ],
      ),
    );
  }
}

class DocPrefillTab extends StatefulWidget {
  final DocPlatformRouter router;
  final UserProfileStore profileStore;

  const DocPrefillTab({
    super.key,
    required this.router,
    required this.profileStore,
  });

  @override
  State<DocPrefillTab> createState() => _DocPrefillTabState();
}

class _DocPrefillTabState extends State<DocPrefillTab> {
  final _urlCtrl = TextEditingController();
  final _formKey = GlobalKey<FormBuilderState>();
  DocPlatform? _detectedPlatform;
  List<UnifiedDocField> _fields = [];
  Map<String, dynamic> _prefilled = {};
  bool _loading = false;
  bool _submitting = false;

  Future<void> _parseDocUrl([String? presetUrl]) async {
    final url = (presetUrl ?? _urlCtrl.text).trim();
    if (url.isEmpty) return;
    if (presetUrl != null) _urlCtrl.text = presetUrl;

    setState(() {
      _loading = true;
      _fields = [];
      _prefilled = {};
    });

    try {
      final adapter = widget.router.resolve(url);
      final engine = PrefillEngine(
        adapter: adapter,
        profileStore: widget.profileStore,
      );
      final fields = await adapter.fetchFields(url);
      final result = await engine.execute(docUrl: url, autoSubmit: false);

      setState(() {
        _detectedPlatform = adapter.platform;
        _fields = fields;
        _prefilled = result.prefilledData;
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        _formKey.currentState?.patchValue(_prefilled);
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('解析失败：$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submitForm() async {
    if (!(_formKey.currentState?.saveAndValidate() ?? false)) return;
    setState(() => _submitting = true);
    try {
      final adapter = widget.router.resolve(_urlCtrl.text.trim());
      final ok = await adapter.submitRecord(
        _urlCtrl.text.trim(),
        _formKey.currentState!.value,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ok ? '文档表单提交成功' : '提交失败，请重试')),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('文档快速填报')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _urlCtrl,
            decoration: InputDecoration(
              labelText: '粘贴微信/腾讯文档、飞书或金山文档链接',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                onPressed: _loading ? null : () => _parseDocUrl(),
                icon: const Icon(Icons.search),
              ),
            ),
            onSubmitted: (_) => _parseDocUrl(),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: [
              ActionChip(
                label: const Text('示例：腾讯文档'),
                onPressed: () =>
                    _parseDocUrl('https://docs.qq.com/form/page/demo_tencent'),
              ),
              ActionChip(
                label: const Text('示例：飞书多维表'),
                onPressed: () =>
                    _parseDocUrl('https://demo.feishu.cn/base/demo_bitable'),
              ),
              ActionChip(
                label: const Text('示例：金山文档'),
                onPressed: () =>
                    _parseDocUrl('https://www.kdocs.cn/l/demo_kdocs'),
              ),
            ],
          ),
          if (_loading) ...[
            const SizedBox(height: 24),
            const Center(child: CircularProgressIndicator()),
          ],
          if (_fields.isNotEmpty) ...[
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Chip(label: Text(_detectedPlatform?.displayName ?? '')),
                TextButton.icon(
                  onPressed: () => _formKey.currentState?.patchValue(_prefilled),
                  icon: const Icon(Icons.auto_fix_high),
                  label: const Text('重新预填充'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            FormBuilder(
              key: _formKey,
              initialValue: _prefilled,
              child: Column(
                children: [
                  ..._fields.map((field) {
                    final matched = _prefilled.containsKey(field.fieldId);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: FormBuilderTextField(
                        name: field.fieldId,
                        decoration: InputDecoration(
                          labelText:
                              field.required ? '${field.label} *' : field.label,
                          border: const OutlineInputBorder(),
                          suffixIcon: matched
                              ? const Icon(Icons.check_circle, color: Colors.green)
                              : null,
                        ),
                        validator: (val) {
                          if (field.required &&
                              (val == null || val.trim().isEmpty)) {
                            return '请填写 ${field.label}';
                          }
                          return null;
                        },
                      ),
                    );
                  }),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _submitting ? null : _submitForm,
                      child: _submitting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('确认并提交文档'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class UserProfileTab extends StatefulWidget {
  final UserProfileStore profileStore;
  const UserProfileTab({super.key, required this.profileStore});

  @override
  State<UserProfileTab> createState() => _UserProfileTabState();
}

class _UserProfileTabState extends State<UserProfileTab> {
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _deptCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await widget.profileStore.getDecryptedProfile();
    _nameCtrl.text = p['name']?.toString() ?? '';
    _phoneCtrl.text = p['phone']?.toString() ?? '';
    _emailCtrl.text = p['email']?.toString() ?? '';
    _deptCtrl.text = p['department']?.toString() ?? '';
  }

  Future<void> _save() async {
    await widget.profileStore.saveProfile({
      'name': _nameCtrl.text.trim(),
      'phone': _phoneCtrl.text.trim(),
      'email': _emailCtrl.text.trim(),
      'department': _deptCtrl.text.trim(),
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已加密保存本地预填充档案')),
      );
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _deptCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('本地加密个人档案')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
              labelText: '姓名',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _phoneCtrl,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: '手机号码',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: '电子邮箱',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _deptCtrl,
            decoration: const InputDecoration(
              labelText: '所属部门 / 学院',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.lock_outline),
            label: const Text('加密保存档案'),
          ),
        ],
      ),
    );
  }
}

class GitHubAnalyzerTab extends StatefulWidget {
  const GitHubAnalyzerTab({super.key});

  @override
  State<GitHubAnalyzerTab> createState() => _GitHubAnalyzerTabState();
}

class _GitHubAnalyzerTabState extends State<GitHubAnalyzerTab> {
  final _keywordCtrl = TextEditingController(text: 'form');
  final _service = GitHubAnalyzerService();
  List<RepoQualityReport> _reports = [];
  bool _loading = false;
  String? _error;

  Future<void> _search() async {
    final kw = _keywordCtrl.text.trim();
    if (kw.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await _service.searchAndEvaluate(keyword: kw, limit: 5);
      setState(() => _reports = res);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _keywordCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('GitHub 项目分析')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _keywordCtrl,
              decoration: InputDecoration(
                labelText: '输入关键词搜索 Dart/Flutter 开源项目',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  onPressed: _loading ? null : _search,
                  icon: const Icon(Icons.search),
                ),
              ),
              onSubmitted: (_) => _search(),
            ),
            const SizedBox(height: 12),
            if (_loading) const LinearProgressIndicator(),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
              ),
            Expanded(
              child: ListView.builder(
                itemCount: _reports.length,
                itemBuilder: (context, index) {
                  final r = _reports[index];
                  return Card(
                    margin: const EdgeInsets.only(top: 10),
                    child: ListTile(
                      title: Text(r.fullName),
                      subtitle: Text(
                        '⭐ ${r.stars}  |  👥 ${r.contributorsCount} 贡献者\n${r.evaluationSummary}',
                      ),
                      trailing: CircleAvatar(
                        child: Text(r.qualityGrade),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
