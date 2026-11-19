import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quick_doc_filler/core/storage/secure_token_store.dart';
import 'package:quick_doc_filler/features/github_analyzer/data/github_analyzer_service.dart';
import 'package:webview_flutter/webview_flutter.dart';

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

  @override
  Widget build(BuildContext context) {
    final pages = [
      DocLaunchTab(profileStore: _profileStore),
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
            label: '网页快填',
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

/// 首页：粘贴任意收集表链接，进入内置浏览器一键填表
class DocLaunchTab extends StatefulWidget {
  final UserProfileStore profileStore;

  const DocLaunchTab({super.key, required this.profileStore});

  @override
  State<DocLaunchTab> createState() => _DocLaunchTabState();
}

class _DocLaunchTabState extends State<DocLaunchTab> {
  final _urlCtrl = TextEditingController();

  void _openInWebView([String? presetUrl]) {
    var raw = (presetUrl ?? _urlCtrl.text).trim();
    if (raw.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先粘贴需要填写的文档或收集表链接')),
      );
      return;
    }
    if (!raw.startsWith('http://') && !raw.startsWith('https://')) {
      raw = 'https://$raw';
    }
    _urlCtrl.text = raw;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WebFormFillPage(
          initialUrl: raw,
          profileStore: widget.profileStore,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('文档网页快填（免费本地版）')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _urlCtrl,
            decoration: const InputDecoration(
              labelText: '粘贴腾讯文档、飞书、金山文档或任意表单链接',
              hintText: 'https://docs.qq.com/form/...',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _openInWebView(),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => _openInWebView(),
              icon: const Icon(Icons.open_in_browser),
              label: const Text('打开网页并一键自动填表'),
            ),
          ),
          const SizedBox(height: 20),
          const Text('常用平台快捷入口',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ActionChip(
                label: const Text('腾讯文档'),
                onPressed: () => _openInWebView('https://docs.qq.com/'),
              ),
              ActionChip(
                label: const Text('飞书文档'),
                onPressed: () => _openInWebView('https://www.feishu.cn/'),
              ),
              ActionChip(
                label: const Text('金山文档'),
                onPressed: () => _openInWebView('https://www.kdocs.cn/'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(14),
              child: Text(
                '使用说明：\n'
                '1. 先在底部「个人档案」填好姓名、手机号、邮箱、学号/工号、部门并加密保存。\n'
                '2. 在上方粘贴任意收集表链接点打开（如需登录，在网页内正常登录一次即可记住状态）。\n'
                '3. 页面加载完成后，点右上角「一键填表」，自动把档案填入对应输入框，核对后直接点网页提交。',
              )
