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

/// 腾讯文档全自动填写 UI 脚本（打开 docs.qq.com/form/* 自动挂载）
const String kTencentDocsUserScript = r'''
(function() {
    'use strict';
    if (window.__txwd_ui_injected) return;
    window.__txwd_ui_injected = true;

    const defaultUIConfig = {
        scheduledRefreshTime: "23:29:00",
        startTime: "2026-11-19T23:29:00",
        timing: { initialWait: 20, submitDelay: 0 },
        fill: [{ key: "班级", value: "8" }, { key: "姓名", value: "张三" }],
        radio: [{ key: "学号", value: "12345" }, { key: "年级", value: "2024" }],
        checkbox: [{ key: "时间", value: "星期一" }]
    };
    const savedConfig = JSON.parse(localStorage.getItem("txwd_ui_config") || "null");
    const uiConfig = savedConfig || defaultUIConfig;

    const style = `
        .floating-panel {
            position: fixed; top: 8%; right: 5%; z-index: 10000;
            width: 90%; max-width: 350px;
            background: linear-gradient(135deg, #ffecd2, #fcb69f);
            border: 1px solid #ccc; box-shadow: 0 2px 10px rgba(0,0,0,0.3);
            font-size: 14px; padding: 10px; border-radius: 8px;
            max-height: 80vh; overflow-y: auto;
        }
        .floating-panel h4 { margin: 0 0 10px; color: #333; }
        .section { margin-bottom: 10px; }
        .section-title { font-weight: bold; margin-bottom: 5px; color: #333; }
        .entry { display: flex; gap: 5px; margin-bottom: 5px; flex-wrap: wrap; }
        .entry input { flex: 1; max-width: 105px; font-size: 14px; padding: 3px; }
        .floating-panel button { border: none; border-radius: 4px; padding: 5px; font-size: 14px; }
        #countdown { font-weight: bold; color: #e74c3c; text-align: center; margin-bottom: 10px; }
        #ui_toggleBtn {
            position: fixed; bottom: 24px; right: 20px; z-index: 11000;
            background: linear-gradient(135deg, #6a11cb, #2575fc);
            color: #fff; border: none; border-radius: 50%;
            width: 52px; height: 52px; font-size: 15px;
            box-shadow: 0 2px 8px rgba(0,0,0,0.35);
        }
    `;
    const html = `
        <div class="floating-panel" id="ui_panel">
            <h4>腾讯文档自动填写面板</h4>
            <div class="section">
                <div class="section-title">时间设置</div>
                <label>刷新时间（HH:MM:SS）：</label><br>
                <input type="text" id="refreshTime" value="${uiConfig.scheduledRefreshTime}" style="width:100%;"><br><br>
                <label>允许提交时间（YYYY-MM-DDTHH:MM:SS）：</label><br>
                <input type="text" id="allowSubmitTime" value="${uiConfig.startTime}" style="width:100%;"><br><br>
                <label>提交延迟 (毫秒)：</label><br>
                <input type="number" id="submitDelay" value="${uiConfig.timing.submitDelay}" style="width:100%;"><br><br>
                <div id="countdown">剩余时间：计算中...</div>
            </div>
            <hr>
            <div class="section">
                <div class="section-title">填空题配置</div>
                <div id="fillContainer"></div>
                <button id="addFill" style="background:#6a11cb;color:#fff;width:100%;">＋ 添加填空题</button>
            </div>
            <hr>
            <div class="section">
                <div class="section-title">单选题配置</div>
                <div id="singleContainer"></div>
                <button id="addSingle" style="background:#2575fc;color:#fff;width:100%;">＋ 添加单选题</button>
            </div>
            <hr>
            <div class="section">
                <div class="section-title">多选题配置</div>
                <div id="multipleContainer"></div>
                <button id="addMultiple" style="background:#e67e22;color:#fff;width:100%;">＋ 添加多选题</button>
            </div>
            <hr>
            <button id="saveConfig" style="background:#28a745;color:#fff;width:48%;">保存配置</button>
            <button id="resetConfig" style="background:#dc3545;color:#fff;width:48%;float:right;">重置默认</button>
        </div>
        <button id="ui_toggleBtn">配置</button>
    `;
    const styleTag = document.createElement('style');
    styleTag.textContent = style;
    document.head.appendChild(styleTag);
    const panelContainer = document.createElement('div');
    panelContainer.innerHTML = html;
    document.body.appendChild(panelContainer);

    const uiPanel = document.getElementById('ui_panel');
    const toggleBtn = document.getElementById('ui_toggleBtn');
    uiPanel.style.display = 'none';
    toggleBtn.addEventListener('click', () => {
        uiPanel.style.display = uiPanel.style.display === 'none' ? 'block' : 'none';
    });

    function createEntry(containerId, k = '', v = '') {
        const container = document.getElementById(containerId);
        const div = document.createElement('div');
        div.className = 'entry';
        div.innerHTML = `
            <input type="text" placeholder="题目关键词" value="${k}">
            <input type="text" placeholder="答案" value="${v}">
            <button class="remove">删除</button>
        `;
        div.querySelector('.remove').onclick = () => div.remove();
        container.appendChild(div);
    }

    document.getElementById('addFill').addEventListener('click', () => createEntry('fillContainer'));
    document.getElementById('addSingle').addEventListener('click', () => createEntry('singleContainer'));
    document.getElementById('addMultiple').addEventListener('click', () => createEntry('multipleContainer'));

    (uiConfig.fill || []).forEach(i => createEntry('fillContainer', i.key, i.value));
    (uiConfig.radio || []).forEach(i => createEntry('singleContainer', i.key, i.value));
    (uiConfig.checkbox || []).forEach(i => createEntry('multipleContainer', i.key, i.value));

    function collectEntries(cid) {
        return Array.from(document.getElementById(cid).querySelectorAll('.entry')).map(div => ({
            key: div.querySelector('input:nth-child(1)').value.trim(),
            value: div.querySelector('input:nth-child(2)').value.trim()
        })).filter(item => item.key);
    }

    document.getElementById('saveConfig').addEventListener('click', () => {
        const newCfg = {
            scheduledRefreshTime: document.getElementById('refreshTime').value,
            startTime: document.getElementById('allowSubmitTime').value,
            timing: {
                initialWait: 20,
                submitDelay: parseInt(document.getElementById('submitDelay').value) || 0
            },
            fill: collectEntries('fillContainer'),
            radio: collectEntries('singleContainer'),
            checkbox: collectEntries('multipleContainer')
        };
        localStorage.setItem("txwd_ui_config", JSON.stringify(newCfg));
        alert("配置保存成功，刷新页面后生效！");
    });

    document.getElementById('resetConfig').addEventListener('click', () => {
        localStorage.removeItem("txwd_ui_config");
        alert("已重置默认配置，刷新页面后恢复默认！");
    });

    let refreshTimer, nextRefreshTime;
    const todayKey = new Date().toISOString().slice(0, 10);
    const refreshedToday = sessionStorage.getItem('txwd_refreshedDate') === todayKey;

    function updateNextRefreshTime() {
        const parts = document.getElementById('refreshTime').value.split(':').map(Number);
        const now = new Date();
        nextRefreshTime = new Date(now.getFullYear(), now.getMonth(), now.getDate(), parts[0] || 0, parts[1] || 0, parts[2] || 0);
        if (nextRefreshTime <= now) nextRefreshTime.setDate(nextRefreshTime.getDate() + 1);
    }
    updateNextRefreshTime();

    function startCountdown() {
        const cd = document.getElementById('countdown');
        if (refreshedToday) {
            cd.textContent = '今日已刷新';
            return;
        }
        clearInterval(refreshTimer);
        refreshTimer = setInterval(() => {
            const diff = Math.floor((nextRefreshTime - new Date()) / 1000);
            if (diff > 0) {
                cd.textContent = `剩余时间：${diff} 秒`;
            } else {
                cd.textContent = '正在刷新...';
                clearInterval(refreshTimer);
                sessionStorage.setItem('txwd_refreshedDate', todayKey);
                location.reload();
            }
        }, 1000);
    }
    startCountdown();
    document.getElementById('refreshTime').addEventListener('change', () => {
        sessionStorage.removeItem('txwd_refreshedDate');
        updateNextRefreshTime();
        startCountdown();
    });

    const stored = JSON.parse(localStorage.getItem("txwd_ui_config") || "null") || defaultUIConfig;
    const answers = {};
    (stored.fill || []).forEach(i => i.key && (answers[i.key] = i.value));
    (stored.radio || []).forEach(i => i.key && (answers[i.key] = i.value));
    (stored.checkbox || []).forEach(i => {
        if (i.key) {
            const arr = i.value.split(/[,，]/).map(s => s.trim()).filter(Boolean);
            answers[i.key] = { answers: arr, select: { count: arr.length, mode: "random" } };
        }
    });
    const config = {
        scheduledRefreshTime: stored.scheduledRefreshTime,
        startTime: stored.startTime,
        timing: stored.timing,
        answers
    };

    class FormFiller {
        async execute() {
            await this.waitForPageReady();
            await this.fillAllQuestions();
            await this.handleSubmission();
        }
        waitForPageReady() {
            return new Promise(res => {
                const ck = setInterval(() => {
                    if (document.querySelector('.question')) {
                        clearInterval(ck);
                        setTimeout(res, config.timing.initialWait);
                    }
                }, 200);
            });
        }
        fuzzyMatch(a, b) {
            if (!a || !b) return false;
            const normalize = str => str.toLowerCase().replace(/[^\w\u4e00-\u9fa5]/g, '').trim();
            return normalize(b).includes(normalize(a));
        }
        async fillInput(q, v) {
            const inp = q.querySelector('textarea') || q.querySelector('input');
            if (!inp) return;
            inp.focus();
            const proto = inp.tagName === 'TEXTAREA'
                ? window.HTMLTextAreaElement.prototype
                : window.HTMLInputElement.prototype;
            const setter = Object.getOwnPropertyDescriptor(proto, 'value')?.set;
            if (setter) setter.call(inp, String(v));
            else inp.value = String(v);
            ['input', 'change', 'blur'].forEach(e => inp.dispatchEvent(new Event(e, { bubbles: true })));
        }
        handleRadio(q, cfg) {
            const opts = Array.from(q.querySelectorAll('[role="radio"]'));
            const target = cfg.answer || cfg;
            const match = opts.find(o => {
                const txt = o.querySelector('.form-choice-option-text-content')?.textContent || o.textContent;
                return txt && this.fuzzyMatch(target, txt);
            });
            if (match) match.click();
        }
        handleCheckbox(q, cfg) {
            const opts = Array.from(q.querySelectorAll('[role="checkbox"]'));
            const arr = cfg.answers || [];
            const sel = opts.filter(o => {
                const txt = o.querySelector('.form-choice-option-text-content')?.textContent || o.textContent;
                return txt && arr.some(a => this.fuzzyMatch(a, txt));
            });
            sel.slice(0, cfg.select.count).forEach(o => o.click());
        }
        async fillAllQuestions() {
            for (const q of document.querySelectorAll('.question')) {
                const title = q.querySelector('.question-title')?.textContent;
                if (!title) continue;
                for (const [k, v] of Object.entries(config.answers)) {
                    if (!this.fuzzyMatch(k, title)) continue;
                    if (q.querySelector('textarea') || q.querySelector('input[type="text"]')) {
                        await this.fillInput(q, v);
                    } else if (q.querySelector('[role="radio"]')) {
                        this.handleRadio(q, v);
                    } else if (q.querySelector('[role="checkbox"]')) {
                        this.handleCheckbox(q, v);
                    }
                }
            }
        }
        async handleSubmission() {
            await new Promise(r => setTimeout(r, config.timing.submitDelay));
            if (new Date() < new Date(config.startTime)) return;
            const btn = document.querySelector('.question-commit button');
            if (btn && !btn.disabled) {
                btn.click();
                await this.handleConfirm();
            }
        }
        async handleConfirm() {
            return new Promise(res => {
                let attempts = 0;
                const ck = setInterval(() => {
                    const cbtn = document.querySelector('.dui-modal-footer-ok:not([disabled])');
                    if (cbtn) {
                        clearInterval(ck);
                        cbtn.click();
                        setTimeout(() => { location.reload(); res(); }, 500);
                    } else if (++attempts > 8) {
                        clearInterval(ck);
                        res();
                    }
                }, 300);
            });
        }
    }
    new FormFiller().execute();
})();
''';

/// 通用自定义自动填表规则模型
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

/// 返回可变列表（修复只读 const 列表导致无法保存修改的问题）
List<CustomFillRule> defaultFillRules() => [
      const CustomFillRule(title: '姓名', keywords: '姓名,名字,填报人,联系人,真实姓名,name', value: ''),
      const CustomFillRule(title: '手机号码', keywords: '手机,电话,联系方式,联系电话,mobile,phone,tel', value: ''),
      const CustomFillRule(title: '电子邮箱', keywords: '邮箱,电子邮箱,email,mail', value: ''),
      const CustomFillRule(title: '学号 / 工号', keywords: '学号,工号,编号,员工号,student', value: ''),
      const CustomFillRule(title: '部门 / 学院', keywords: '部门,学院,单位,班级,公司,专业,组织', value: ''),
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
      appBar: AppBar(title: const Text('文档网页快填（自动/定时版）')),
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
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('进入网页自动填写（无需手动点）'),
            subtitle: const Text('页面加载完成后自动按自定义词条填入'),
            value: _autoFillOnLoad,
            onChanged: (v) => setState(() => _autoFillOnLoad = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('启用定时自动刷新并填表'),
            subtitle: const Text('到设定时间自动刷新网页并瞬间自动填写'),
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
              icon: const Icon(Icons.open_in_browser),
              label: Text(_enableSchedule ? '打开网页并启动定时填表' : '打开网页并自动填表'),
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
  final String? scheduledTime; // 格式 HH:MM:SS

  const WebFormFillPage({
    super.key,
    required this.initialUrl,
    required this.profileStore,
    this.autoFillOnLoad = true,
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
  bool _pendingScheduledFill = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (p) {
            if (mounted) setState(() => _progress = p);
          },
          onPageFinished: (url) async {
            // 腾讯文档收集表自动挂载悬浮配置面板
            if (url.contains('docs.qq.com/form')) {
              await _controller.runJavaScript(kTencentDocsUserScript);
            }
            // 进入网页自动填表，或定时刷新触发后的自动填表
            if (widget.autoFillOnLoad || _pendingScheduledFill) {
              _pendingScheduledFill = false;
              await _autoFillWithRetry();
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.initialUrl));

    if (widget.scheduledTime != null && widget.scheduledTime!.isNotEmpty) {
      _startScheduleCountdown(widget.scheduledTime!);
    }
  }

  /// 启动定时刷新倒计时，到点自动 reload 并在加载完成瞬间自动填写
  void _startScheduleCountdown(String timeStr) {
    final parts = timeStr.split(':').map((e) => int.tryParse(e.trim()) ?? 0).toList();
    if (parts.length < 2) return;
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
          _countdownText = '已到点！正在自动刷新并填写...';
          _pendingScheduledFill = true;
        });
        _controller.reload();
      } else {
        final h = diff.inHours.toString().padLeft(2, '0');
        final m = (diff.inMinutes % 60).toString().padLeft(2, '0');
        final s = (diff.inSeconds % 60).toString().padLeft(2, '0');
        setState(() {
          _countdownText = '距离 ${widget.scheduledTime} 自动刷新填表还剩 $h:$m:$s';
        });
      }
    });
  }

  /// 针对异步渲染的网页表单，在加载完 0.8 秒和 2.2 秒自动探测填充
  Future<void> _autoFillWithRetry() async {
    await Future<void>.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;
    final firstCount = await _autoFillCurrentPage(silentIfZero: true);
    if (firstCount == 0 && mounted) {
      await Future<void>.delayed(const Duration(milliseconds: 1400));
      if (!mounted) return;
      await _autoFillCurrentPage(silentIfZero: true);
    }
  }

  Future<int> _autoFillCurrentPage({bool silentIfZero = false}) async {
    final allRules = await loadFillRules(widget.profileStore);
    final activeRules = allRules
        .where((r) => r.value.trim().isNotEmpty && r.keywords.trim().isNotEmpty)
        .map((r) => {
              'words': r.keywords
                  .split(RegExp(r'[,，、/\s]+'))
                  .map((w) => w.trim().toLowerCase())
                  .where((w) => w.isNotEmpty)
                  .toList(),
              'value': r.value.trim(),
            })
        .toList();

    if (activeRules.isEmpty) {
      if (!silentIfZero && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请先在「自定义词条」中填写至少一项内容')),
        );
      }
      return 0;
    }

    final rulesJson = jsonEncode(activeRules);
    final js = '''
(function(rules) {
  function setNativeValue(el, value) {
    const proto = el.tagName === 'TEXTAREA'
      ? window.HTMLTextAreaElement.prototype
      : window.HTMLInputElement.prototype;
    const setter = Object.getOwnPropertyDescriptor(proto, 'value')?.set;
    if (setter) setter.call(el, value);
    else el.value = value;
    el.dispatchEvent(new Event('input', { bubbles: true }));
    el.dispatchEvent(new Event('change', { bubbles: true }));
    el.dispatchEvent(new Event('blur', { bubbles: true }));
  }

  function getContextText(el) {
    let parts = [
      el.getAttribute('placeholder') || '',
      el.getAttribute('aria-label') || '',
      el.getAttribute('name') || '',
      el.getAttribute('id') || ''
    ];
    let parent = el.parentElement;
    for (let i = 0; i < 4 && parent; i++) {
      const txt = (parent.innerText || '').trim();
      if (txt.length > 0 && txt.length < 150) {
        parts.push(txt);
        break;
      }
      parent = parent.parentElement;
    }
    return parts.join(' ').toLowerCase();
  }

  let filledCount = 0;
  const inputs = document.querySelectorAll('input, textarea, [contenteditable="true"]');
  inputs.forEach(el => {
    const type = (el.getAttribute('type') || '').toLowerCase();
    if (['hidden', 'submit', 'button', 'checkbox', 'radio', 'file', 'password'].includes(type)) {
      return;
    }
    if (el.offsetParent === null) return;

    const hint = getContextText(el);
    let bestValue = null;
    let bestLen = 0;

    for (const rule of rules) {
      for (const w of rule.words) {
        if (w && hint.includes(w) && w.length > bestLen) {
          bestLen = w.length;
          bestValue = rule.value;
        }
      }
    }

    if (bestValue !== null) {
      if (el.getAttribute('contenteditable') === 'true') {
        el.innerText = bestValue;
        el.dispatchEvent(new Event('input', { bubbles: true }));
      } else {
        setNativeValue(el, bestValue);
      }
      filledCount++;
    }
  });
  return filledCount;
})($rulesJson);
''';

    try {
      final result = await _controller.runJavaScriptReturningResult(js);
      final count = int.tryParse(result.toString()) ?? 0;
      if (mounted && (count > 0 || !silentIfZero)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              count > 0
                  ? '已自动填充 $count 个字段，请核对后提交'
                  : '未匹配到输入框，可在「自定义词条」里补充题干关键词',
            ),
          ),
        );
      }
      return count;
    } catch (e) {
      if (!silentIfZero && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('自动填充执行失败：$e')),
        );
      }
      return 0;
    }
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
              onPressed: () => _autoFillCurrentPage(silentIfZero: false),
              icon: const Icon(Icons.auto_fix_high, size: 18),
              label: const Text('手动补填'),
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
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                      setState(() => _countdownText = null);
                    },
                    child: const Text('取消'),
                  ),
                ],
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
                  labelText: '字段名称（如：微信号、身份证号）',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: keywordsCtrl,
                decoration: const InputDecoration(
                  labelText: '匹配关键词（多个用逗号隔开）',
                  hintText: '例如：微信号,微信,WeChat',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: valueCtrl,
                decoration: const InputDecoration(
                  labelText: '自动填写的内容',
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
