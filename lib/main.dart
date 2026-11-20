import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quick_doc_filler/core/storage/secure_token_store.dart';
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

  /// 自动从微信/QQ/飞书整段分享文案中提取有效网址，忽略前后中文文字
  String? _extractUrl(String input) {
    final match = RegExp(
      r'https?://[^\s\u4e00-\u9fa5，。！？、）】》"<>]+',
      caseSensitive: false,
    ).firstMatch(input);
    if (match != null) return match.group(0);
    final trimmed = input.trim();
    if (trimmed.contains('.') &&
        !trimmed.contains(' ') &&
        !trimmed.contains('\n')) {
      return 'https://$trimmed';
    }
    return null;
  }

  /// 一键粘贴剪贴板并自动提取链接
  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('剪贴板为空')),
        );
      }
      return;
    }
    final cleanUrl = _extractUrl(text);
    setState(() {
      _urlCtrl.text = cleanUrl ?? text;
    });
    if (cleanUrl != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已自动提取链接')),
      );
    }
  }

  void _openInWebView([String? presetUrl]) {
    final raw = (presetUrl ?? _urlCtrl.text).trim();
    if (raw.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先粘贴包含链接的分享文案')),
      );
      return;
    }
    final cleanUrl = _extractUrl(raw);
    if (cleanUrl == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('未识别到有效网址，请确认粘贴内容里包含 https:// 链接')),
      );
      return;
    }
    _urlCtrl.text = cleanUrl;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WebFormFillPage(
          initialUrl: cleanUrl,
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
      appBar: AppBar(title: const Text('文档全自动填报 v2.0')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _urlCtrl,
            minLines: 1,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: '直接粘贴微信/飞书/金山分享文案或链接',
              hintText: '支持整段粘贴，自动提取 https:// 链接',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                tooltip: '一键粘贴并提取链接',
                onPressed: _pasteFromClipboard,
                icon: const Icon(Icons.content_paste),
              ),
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
            subtitle: const Text('自动点击网页提交按钮及确认弹窗'),
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

  function isSelected(el) {
    if (!el) return false;
    if (el.checked === true) return true;
    if (el.getAttribute('aria-checked') === 'true') return true;
    const inner = el.querySelector('input[type="radio"], input[type="checkbox"]');
    if (inner && inner.checked) return true;
    const cls = (el.className || '').toString().toLowerCase();
    return cls.includes('checked') || cls.includes('selected') || cls.includes('active');
  }

  function simulateTap(el) {
    if (!el) return;
    try { el.scrollIntoView({ block: 'center' }); } catch (e) {}
    ['pointerdown', 'mousedown', 'pointerup', 'mouseup', 'click'].forEach(type => {
      el.dispatchEvent(new MouseEvent(type, { bubbles: true, cancelable: true, view: window }));
    });
    if (typeof el.click === 'function') el.click();
  }

  function optionText(el) {
    const tEl = el.querySelector('.form-choice-option-text-content, .option-text, span, label');
    return (tEl ? tEl.textContent : el.textContent) || '';
  }

  function selectChoiceInContainer(container, val, isMulti) {
    const wantedList = isMulti
      ? val.split(/[,，、]/).map(s => norm(s)).filter(Boolean)
      : [norm(val)];

    const selector = isMulti
      ? '[role="checkbox"], .form-choice-option, label'
      : '[role="radio"], .form-choice-option, label';

    const candidates = Array.from(container.querySelectorAll(selector)).filter(el => {
      if (el.offsetParent === null) return false;
      const txt = norm(optionText(el));
      return txt.length > 0;
    });

    let hit = 0;
    for (const wanted of wantedList) {
      if (!wanted) continue;
      let target = candidates.find(el => norm(optionText(el)) === wanted) ||
                   candidates.find(el => norm(optionText(el)).includes(wanted));
      if (target) {
        if (!isSelected(target)) {
          simulateTap(target);
        }
        hit++;
        if (!isMulti) break;
      }
    }
    return hit;
  }

  function fillFormOnce() {
    let filled = 0;

    // 1. 腾讯文档及结构化题目块（优先处理单选/多选，再处理填空）
    const questions = document.querySelectorAll('.question, .form-question, [data-question-id]');
    if (questions.length > 0) {
      questions.forEach(q => {
        const titleEl = q.querySelector('.question-title, .title, h3, h4') || q;
        const val = matchRule(titleEl.textContent || '');
        if (!val) return;

        const hasRadio = q.querySelector('[role="radio"], input[type="radio"]');
        if (hasRadio) {
          filled += selectChoiceInContainer(q, val, false);
          return;
        }

        const hasCheck = q.querySelector('[role="checkbox"], input[type="checkbox"]');
        if (hasCheck) {
          filled += selectChoiceInContainer(q, val, true);
          return;
        }

        const inp = q.querySelector('textarea, input[type="text"], input[type="tel"], input[type="email"], input[type="number"], input:not([type])');
        if (inp && inp.offsetParent !== null) {
          setNativeValue(inp, val);
          filled++;
        }
      });
    }

    // 2. 通用网页兜底：原生单选组
    const nativeRadios = Array.from(document.querySelectorAll('input[type="radio"]'));
    const radioGroups = {};
    nativeRadios.forEach(r => {
      const name = r.name || '__unnamed';
      if (!radioGroups[name]) radioGroups[name] = [];
      radioGroups[name].push(r);
    });
    Object.values(radioGroups).forEach(group => {
      if (group.some(r => r.checked)) return;
      let container = group[0].parentElement;
      for (let i = 0; i < 4 && container && container.parentElement; i++) {
        if (container.querySelectorAll('input[type="radio"]').length >= group.length) break;
        container = container.parentElement;
      }
      if (!container) return;
      const val = matchRule(container.innerText || '');
      if (!val) return;
      const wanted = norm(val);
      for (const r of group) {
        const lbl = (r.id ? document.querySelector('label[for="' + r.id + '"]') : null) || r.closest('label') || r.parentElement;
        const txt = norm(lbl ? lbl.textContent : r.value);
        if (txt && (txt === wanted || txt.includes(wanted))) {
          simulateTap(lbl || r);
          filled++;
          break;
        }
      }
    });

    // 3. 通用网页兜底：填空输入框
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
    simulateTap(btn);
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
        simulateTap(okBtn);
        report('自动填写并提交完成！');
      } else if (++tries >= 10) {
        clearInterval(ck);
        report('已触发提交（无二次弹窗或已提交成功）');
      }
    }, 300);
  }

  if (window.__qdf_poll) clearInterval(window.__qdf_poll);
  let attempts = 0;
  window.__qdf_poll = setInterval(() => {
    attempts++;
    const hasForm = document.querySelector('.question, [role="radio"], input:not([type="hidden"]), textarea, [contenteditable="true"]');
    if (hasForm) {
      const count = fillFormOnce();
      if (count > 0) {
        clearInterval(window.__qdf_poll);
        report('已自动填写/选中 ' + count + ' 项' + (shouldSubmit ? '，即将自动提交...' : '，请核对后提交'));
        if (shouldSubmit) {
          setTimeout(triggerSubmit, 450);
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
                  labelText: '字段名称（如：姓名、性别、年级）',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: keywordsCtrl,
                decoration: const InputDecoration(
                  labelText: '匹配关键词（多个用逗号隔开）',
                  hintText: '例如：年级,所在年级',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: valueCtrl,
                decoration: const InputDecoration(
                  labelText: '填写内容 / 单选或多选选项文字',
                  hintText: '例如：2024（多选用逗号隔开）',
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
                      '填入/选中：${isEmpty ? "（未填写，点此编辑）" : rule.value}\n'
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
