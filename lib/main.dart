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

/// 自定义自动填表规则模型
class CustomFillRule {
  final String title;    // 字段展示名，例如：微信号
  final String keywords; // 匹配关键词（逗号分隔），例如：微信号,微信,wechat
  final String value;    // 自动填入的内容

  const CustomFillRule({
    required this.title,
    required this.keywords,
    required this.value,
  });

  Map<String, dynamic> toJson() => {
        'title': title,
        'keywords': keywords,
        'value': value,
      };

  factory CustomFillRule.fromJson(Map<String, dynamic> json) {
    return CustomFillRule(
      title: json['title']?.toString() ?? '',
      keywords: json['keywords']?.toString() ?? '',
      value: json['value']?.toString() ?? '',
    );
  }
}

/// 默认初始模板（用户可在 App 内随意修改、删除或新增）
List<CustomFillRule> defaultFillRules() => const [
      CustomFillRule(title: '姓名', keywords: '姓名,名字,填报人,联系人,真实姓名,name', value: ''),
      CustomFillRule(title: '手机号码', keywords: '手机,电话,联系方式,联系电话,mobile,phone,tel', value: ''),
      CustomFillRule(title: '电子邮箱', keywords: '邮箱,电子邮箱,email,mail', value: ''),
      CustomFillRule(title: '学号 / 工号', keywords: '学号,工号,编号,员工号,student', value: ''),
      CustomFillRule(title: '部门 / 学院', keywords: '部门,学院,单位,班级,公司,专业,组织', value: ''),
      CustomFillRule(title: '常用地址', keywords: '地址,住址,宿舍,address', value: ''),
    ];

Future<List<CustomFillRule>> loadFillRules(UserProfileStore store) async {
  final raw = await store.getDecryptedProfile();
  final list = raw['custom_rules'];
  if (list is List && list.isNotEmpty) {
    return list
        .whereType()
        .map((e) => CustomFillRule.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }
  return defaultFillRules();
}

Future<void> saveFillRules(
  UserProfileStore store,
  List<CustomFillRule> rules,
) async {
  await store.saveProfile({
    'custom_rules': rules.map((r) => r.toJson()).toList(),
  });
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
      CustomRulesTab(profileStore: _profileStore),
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
            icon: Icon(Icons.tune),
            label: '自定义词条',
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
        children:
