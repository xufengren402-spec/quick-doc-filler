import 'dart:async';
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

/// 自定义自动填表规则模型（同时支持填空、单选、多选）
class CustomFillRule {
  final String title;
  final String keywords;
  final String value;

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

List<CustomFillRule> defaultFillRules() => [
      const CustomFillRule(title: '姓名', keywords: '姓名,名字,填报人,联系人,真实姓名,name', value: ''),
      const CustomFillRule(title: '手机号码', keywords: '手机,电话,联系方式,联系电话,mobile,phone,tel', value: ''),
      const CustomFillRule(title: '电子邮箱', keywords: '邮箱,电子邮箱,email,mail', value: ''),
      const CustomFillRule(title: '学号 / 工号', keywords: '学号,工号,编号,员工号,student', value: ''),
      const CustomFillRule(title: '班级 / 部门 / 学院', keywords: '班级,部门,学院,单位,公司,专业,年级,组织', value: ''),
      const CustomFillRule(title: '常用地址', keywords: '地址,住址,宿舍,address', value: ''),
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

class DocLaunchTab extends StatefulWidget {
  final UserProfileStore profileStore;
  const DocLaunchTab({super.key, required this.profileStore});

  @override
  State<DocLaunchTab> createState() => _DocLaunchTabState();
}

class _DocLaunchTabState extends State<DocLaunchTab> {
  final _urlCtrl = TextEditingController();
  final _scheduleTimeCtrl = TextEditingController(text: '23:29:00');
  bool _autoFillOnLoad = true;
  bool _autoSubmit = true;
  bool _enableSchedule = false;

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
          autoFillOnLoad: _autoFillOnLoad,
          autoSubmit: _autoSubmit,
          scheduledTime: _enableSchedule ? _scheduleTimeCtrl.text.trim() : null,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _scheduleTimeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('文档全自动填报')),
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
          const SizedBox(height: 10),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('进入网页自动填写（等待题目出现即填）'),
            value: _autoFillOnLoad,
            onChanged: (v) => setState(() => _autoFillOnLoad = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('填完后自动点击提交'),
            subtitle: const Text('自动点击网页提交按钮及腾讯文档确认弹窗'),
            value: _autoSubmit,
            onChanged: (v) => setState(() => _autoSubmit = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('启用定时刷新并自动填报'),
            subtitle: const Text('到设定时间自动刷新页面、填表并提交'),
            value: _enableSchedule,
            onChanged: (v) => setState(() => _enableSchedule = v),
          ),
          if (_enableSchedule) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _scheduleTimeCtrl,
              decoration: const InputDecoration(
                labelText: '定时触发时间（24小时制 HH:MM:SS）',
                hintText: '例如：23:29:00',
                prefixIcon: Icon(Icons.schedule),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
          ],
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => _openInWebView(),
              icon: const Icon(Icons.rocket_launch_outlined),
              label: Text(_enableSchedule ? '打开网页并启动定时填报' : '打开网页并全自动填报'),
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
        ],
      ),
    );
  }
}

class WebFormFillPage extends StatefulWidget {
  final String initialUrl;
  final UserProfileStore profileStore;
  final bool autoFillOnLoad;
  final bool autoSubmit;
  final String? scheduledTime;

  const WebFormFillPage({
    super.key,
    required this.initialUrl,
    required this.profileStore,
    this.autoFillOnLoad = true,
    this.autoSubmit = true,
    this.scheduledTime,
  });

  @override
  State<WebFormFillPage> createState() => _WebFormFillPageState();
}

class _WebFormFillPageState extends State<WebFormFillPage> {
  late final WebViewController _controller;
  int _progress = 0;
  Timer? _scheduleTimer;
  String? _countdownText;
  String _statusBanner = '正在加载网页...';
  bool _waitingForSchedule = false;

  @override
  void initState() {
    super.initState();
    _waitingForSchedule =
        widget.scheduledTime != null && widget.scheduledTime!.isNotEmpty;

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'AppBridge',
        onMessageReceived: (JavaScriptMessage message) {
          if (!mounted) return;
          setState(() => _statusBanner = message.message);
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (p) {
            if (mounted) setState(() => _progress = p);
          },
          onPageFinished: (url) async {
            if (!mounted) return;
            // 若正在等待定时触发，先只停在页面等待倒计时结束刷新
            if (_waitingForSchedule) {
              setState(() => _statusBanner = '网页已就绪，等待到点自动刷新并填报...');
              return;
            }
            if (widget.autoFillOnLoad) {
              await _injectAutoFillEngine(autoSubmit: widget.autoSubmit);
            } else {
              setState(() => _statusBanner = '网页加载完成，可点击右上角「立即填报」');
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.initialUrl));

    if (_waitingForSchedule) {
      _startScheduleCountdown(widget.scheduledTime!);
    }
  }

  void _startScheduleCountdown(String timeStr) {
    final parts =
        timeStr.split(':').map((e) => int.tryParse(e.trim()) ?? 0).toList();
    if (parts.length < 2) {
      _waitingForSchedule = false;
      return;
    }
    final now = DateTime.now();
    var target = DateTime(
      now.year,
      now.month,
      now.day,
      parts[0].clamp(0, 23),
      parts[1].clamp(0, 59),
      parts.length > 2 ? parts[2].clamp(0, 59) : 0,
    );
    if (!target.isAfter(now)) {
      target = target.add(const Duration(days: 1));
    }

    _scheduleTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final diff = target.difference(DateTime.now());
      if (diff.inMilliseconds <= 0) {
        timer.cancel();
        setState(() {
          _waitingForSchedule = false;
          _countdownText = '已到点！正在自动刷新并执行填报...';
        });
        _controller.reload();
      } else {
        final h = diff.inHours.toString().padLeft(2, '0');
        final m = (diff.inMinutes % 60).toString().padLeft(2, '0');
        final s = (diff.inSeconds % 60).toString().padLeft(2, '0');
        setState(() {
          _countdownText = '距离 ${widget.scheduledTime} 自动刷新填报还剩 $h:$m:$s';
        });
      }
    });
  }

  /// 注入统一自动填表+自动提交引擎（持续轮询等待表单渲染，适配腾讯文档/飞书/金山/通用网页）
  Future<void> _injectAutoFillEngine({required bool autoSubmit}) async {
    final allRules = await loadFillRules(widget.profileStore);
    final activeRules = allRules
        .where((r) => r.value.trim().isNotEmpty && r.keywords.trim().isNotEmpty)
        .map((r) => {
              'title': r.title,
              'words': r.keywords
                  .split(RegExp(r'[,，、/\s]+'))
                  .map((w) => w.trim().toLowerCase())
                  .where((w) => w.isNotEmpty)
                  .toList(),
              'value': r.value.trim(),
            })
        .toList();

    if (activeRules.isEmpty) {
      setState(() => _statusBanner = '未检测到已填写的词条，请先去「自定义词条」保存内容');
      return;
    }

    setState(() => _statusBanner = '正在等待网页表单题目渲染...');
    final rulesJson = jsonEncode(activeRules);

    final js = '''
(function(rules, shouldSubmit) {
  function report(msg) {
    try { if (window.AppBridge) window.AppBridge.postMessage(msg); } catch (e) {}
  }

  function norm(s) {
    return (s || '').toLowerCase().replace(/[^\\w\\u4e00-\\u9fa5]/g, '');
  }

  function matchRule(text) {
    const clean = norm(text);
    if (!clean) return null;
    let best = null;
    let bestLen = 0;
    for (const r of rules) {
      for (const w of r.words) {
        const cw = norm(w);
        if (cw && clean.includes(cw) && cw.length > bestLen) {
          bestLen = cw.length;
          best = r.value;
        }
      }
    }
    return best;
  }

  function setNativeValue(el, val) {
    el.focus();
    const proto = el.tagName === 'TEXTAREA'
      ? window.HTMLTextAreaElement.prototype
      : window.HTMLInputElement.prototype;
    const setter = Object.getOwnPropertyDescriptor(proto, 'value')?.set;
    if (setter) setter.call(el, val);
    else el.value = val;
    ['input', 'change', 'blur'].forEach(ev =>
      el.dispatchEvent(new Event(ev, { bubbles: true }))
    );
  }

  function fillFormOnce() {
    let filled = 0;

    // 1. 优先适配腾讯文档收集表结构（支持填空 + 单选 + 多选）
    const questions = document.querySelectorAll('.question');
    if (questions.length > 0) {
      questions.forEach(q => {
        const titleEl = q.querySelector('.question-title') || q;
        const val = matchRule(titleEl.textContent || '');
        if (!val) return;

        const inp = q.querySelector('textarea, input[type="text"], input:not([type])');
        if (inp) {
          setNativeValue(inp, val);
          filled++;
          return;
        }

        const radios = Array.from(q.querySelectorAll('[role="radio"]'));
        if (radios.length > 0) {
          const target = radios.find(o => {
            const t = o.querySelector('.form-choice-option-text-content')?.textContent || o.textContent || '';
            return norm(t).includes(norm(val));
          });
          if (target) { target.click(); filled++; }
          return;
        }

        const checks = Array.from(q.querySelectorAll('[role="checkbox"]'));
        if (checks.length > 0) {
          const wanted = val.split(/[,，、]/).map(s => norm(s)).filter(Boolean);
          checks.forEach(o => {
            const t = o.querySelector('.form-choice-option-text-content')?.textContent || o.textContent || '';
            if (wanted.some(w => norm(t).includes(w))) {
              o.click();
              filled++;
            }
          });
        }
      });
    }

    // 2. 通用网页表单兜底（飞书、金山文档、问卷星等）
    if (filled === 0) {
      const inputs = document.querySelectorAll('input, textarea, [contenteditable="true"]');
      inputs.forEach(el => {
        const type = (el.getAttribute('type') || '').toLowerCase();
        if (['hidden', 'submit', 'button', 'checkbox', 'radio', 'file', 'password'].includes(type)) return;
        if (el.offsetParent === null) return;

        let ctx = [
          el.getAttribute('placeholder') || '',
          el.getAttribute('aria-label') || '',
          el.getAttribute('name') || '',
          el.getAttribute('id') || ''
        ];
        let p = el.parentElement;
        for (let i = 0; i < 7 && p; i++) {
          const t = (p.innerText || '').trim();
          if (t.length > 0 && t.length < 300) { ctx.push(t); break; }
          p = p.parentElement;
        }
        const val = matchRule(ctx.join(' '));
        if (!val) return;

        if (el.getAttribute('contenteditable') === 'true') {
          el.innerText = val;
          el.dispatchEvent(new Event('input', { bubbles: true }));
        } else {
          setNativeValue(el, val);
        }
        filled++;
      });
    }
    return filled;
  }

  function triggerSubmit() {
    report('正在自动点击提交按钮...');
    let btn = document.querySelector('.question-commit button:not([disabled])');
    if (!btn) {
      const allBtns = Array.from(document.querySelectorAll('button, [role="button"], input[type="submit"]'));
      btn = allBtns.find(b => {
        if (b.disabled || b.offsetParent === null) return false;
        const t = (b.innerText || b.value || '').trim();
        return t === '提交' || t === '确认提交' || t === 'Submit' || t.includes('提交');
      });
    }
    if (!btn) {
      report('已自动填完，但未找到可点击的提交按钮，请手动点提交');
      return;
    }
    btn.click();
    report('已点击提交，正在检测确认弹窗...');

    let tries = 0;
    const ck = setInterval(() => {
      const okBtn = document.querySelector('.dui-modal-footer-ok:not([disabled])') ||
        Array.from(document.querySelectorAll('button')).find(b => {
          const t = (b.innerText || '').trim();
          return b.offsetParent !== null && !b.disabled && (t === '确定' || t === '确认' || t === '确认提交');
        });
      if (okBtn) {
        clearInterval(ck);
        okBtn.click();
        report('自动填写并提交完成！');
      } else if (++tries >= 10) {
        clearInterval(ck);
        report('已触发提交（无二次弹窗或已提交成功）');
      }
    }, 300);
  }

  // 持续轮询等待表单渲染（最多 30 秒，解决 SPA 异步加载和登录跳转）
  if (window.__qdf_poll) clearInterval(window.__qdf_poll);
  let attempts = 0;
  window.__qdf_poll = setInterval(() => {
    attempts++;
    const hasForm = document.querySelector('.question') ||
      document.querySelector('input:not([type="hidden"]), textarea, [contenteditable="true"]');
    if (hasForm) {
      const count = fillFormOnce();
      if (count > 0) {
        clearInterval(window.__qdf_poll);
        report('已自动填写 ' + count + ' 项' + (shouldSubmit ? '，即将自动提交...' : '，请核对后提交'));
        if (shouldSubmit) {
          setTimeout(triggerSubmit, 400);
        }
        return;
      }
    }
    if (attempts >= 60) {
      clearInterval(window.__qdf_poll);
      report('等待超时：未匹配到词条（请确认已登录且关键词与题干一致）');
    }
  }, 500);
})($rulesJson, ${autoSubmit ? 'true' : 'false'});
''';

    await _controller.runJavaScript(js);
  }

  @override
  void dispose() {
    _scheduleTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('网页填报'),
        actions: [
          IconButton(
            tooltip: '刷新页面',
            onPressed: () => _controller.reload(),
            icon: const Icon(Icons.refresh),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton.icon(
              onPressed: () =>
                  _injectAutoFillEngine(autoSubmit: widget.autoSubmit),
              icon: const Icon(Icons.auto_fix_high, size: 18),
              label: const Text('立即填报'),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_countdownText != null)
            Container(
              width: double.infinity,
              color: Colors.amber.shade100,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: [
                  const Icon(Icons.timer, size: 18, color: Colors.deepOrange),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _countdownText!,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.deepOrange,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      _scheduleTimer?.cancel();
                      setState(() {
                        _waitingForSchedule = false;
                        _countdownText = null;
                      });
                    },
                    child: const Text('取消'),
                  ),
                ],
              ),
            ),
          Container(
            width: double.infinity,
            color: Colors.blue.shade50,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Text(
              '状态：$_statusBanner',
              style: TextStyle(fontSize: 13, color: Colors.blue.shade900),
            ),
          ),
          if (_progress < 100)
            LinearProgressIndicator(value: _progress / 100.0),
          Expanded(child: WebViewWidget(controller: _controller)),
        ],
      ),
    );
  }
}

class CustomRulesTab extends StatefulWidget {
  final UserProfileStore profileStore;
  const CustomRulesTab({super.key, required this.profileStore});

  @override
  State<CustomRulesTab> createState() => _CustomRulesTabState();
}

class _CustomRulesTabState extends State<CustomRulesTab> {
  List<CustomFillRule> _rules = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rules = await loadFillRules(widget.profileStore);
    if (mounted) {
      setState(() {
        _rules = List<CustomFillRule>.from(rules);
        _loading = false;
      });
    }
  }

  Future<void> _persist() async {
    try {
      await saveFillRules(widget.profileStore, _rules);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败：$e')),
        );
      }
    }
  }

  Future<void> _showRuleEditor({int? editIndex}) async {
    final existing = editIndex != null ? _rules[editIndex] : null;
    final titleCtrl = TextEditingController(text: existing?.title ?? '');
    final keywordsCtrl = TextEditingController(text: existing?.keywords ?? '');
    final valueCtrl = TextEditingController(text: existing?.value ?? '');

    final saved = await showDialog<CustomFillRule>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(editIndex == null ? '新增自动填写字段' : '编辑自动填写字段'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleCtrl,
                decoration: const InputDecoration(
                  labelText: '字段名称（如：姓名、微信号、年级）',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: keywordsCtrl,
                decoration: const InputDecoration(
                  labelText: '匹配关键词（多个用逗号隔开）',
                  hintText: '例如：姓名,真实姓名,填报人',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: valueCtrl,
                decoration: const InputDecoration(
                  labelText: '自动填写/选中的内容（多选用逗号隔开）',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final title = titleCtrl.text.trim();
              final kw = keywordsCtrl.text.trim();
              final val = valueCtrl.text.trim();
              if (title.isEmpty && kw.isEmpty) return;
              Navigator.of(ctx).pop(
                CustomFillRule(
                  title: title.isEmpty ? kw : title,
                  keywords: kw.isEmpty ? title : kw,
                  value: val,
                ),
              );
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );

    titleCtrl.dispose();
    keywordsCtrl.dispose();
    valueCtrl.dispose();

    if (saved != null) {
      setState(() {
        if (editIndex == null) {
          _rules.add(saved);
        } else {
          _rules[editIndex] = saved;
        }
      });
      await _persist();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已加密保存自定义填表词条')),
        );
      }
    }
  }

  Future<void> _deleteRule(int index) async {
    setState(() => _rules.removeAt(index));
    await _persist();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('自定义自动填表词条')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showRuleEditor(),
        icon: const Icon(Icons.add),
        label: const Text('添加字段'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
              itemCount: _rules.length,
              itemBuilder: (context, index) {
                final rule = _rules[index];
                final isEmpty = rule.value.trim().isEmpty;
                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    onTap: () => _showRuleEditor(editIndex: index),
                    title: Text(rule.title),
                    subtitle: Text(
                      '填入内容：${isEmpty ? "（未填写，点此编辑）" : rule.value}\n'
                      '匹配词：${rule.keywords}',
                    ),
                    trailing: IconButton(
                      tooltip: '删除',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _deleteRule(index),
                    ),
                  ),
                );
              },
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
