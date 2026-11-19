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

/// 腾讯文档全自动填写 UI 脚本（融合自你上传的油猴脚本，打开 docs.qq.com/form/* 自动注入）
const String kTencentDocsUserScript = r'''
(function() {
    'use strict';
    if (window.__txwd_ui_injected) return;
    window.__txwd_ui_injected = true;

    const defaultUIConfig = {
        scheduledRefreshTime: "23:29:00",
        startTime: "2026-11-19T23:29:00",
        timing: { initialWait: 20, submitDelay: 0 },
        fill: [
            { key: "班级", value: "8" },
            { key: "姓名", value: "张三" }
        ],
        radio: [
            { key: "学号", value: "12345" },
            { key: "年级", value: "2024" }
        ],
        checkbox: [
            { key: "时间", value: "星期一" }
        ]
    };
    const savedConfig = JSON.parse(localStorage.getItem("txwd_ui_config") || "null");
    const uiConfig = savedConfig || defaultUIConfig;

    const style = `
        .floating-panel {
            position: fixed;
            top: 8%;
            right: 5%;
            z-index: 10000;
            width: 90%;
            max-width: 350px;
            background: linear-gradient(135deg, #ffecd2, #fcb69f);
            border: 1px solid #ccc;
            box-shadow: 0 2px 10px rgba(0,0,0,0.3);
            font-size: 14px;
            padding: 10px;
            border-radius: 8px;
            max-height: 80vh;
            overflow-y: auto;
        }
        .floating-panel h4 { margin: 0 0 10px; color: #333; }
        .section { margin-bottom: 10px; }
        .section-title { font-weight: bold; margin-bottom: 5px; color: #333; }
        .entry { display: flex; gap: 5px; margin-bottom: 5px; flex-wrap: wrap; }
        .entry input { flex: 1; max-width: 105px; font-size: 14px; padding: 3px; }
        .floating-panel button { border: none; border-radius: 4px; padding: 5px; font-size: 14px; }
        #countdown { font-weight: bold; color: #e74c3c; text-align: center; margin-bottom: 10px; }
        #ui_toggleBtn {
            position: fixed;
            bottom: 24px;
            right: 20px;
            z-index: 11000;
            background: linear-gradient(135deg, #6a11cb, #2575fc);
            color: #fff;
            border: none;
            border-radius: 50%;
            width: 52px;
            height: 52px;
            font-size: 15px;
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
        <button i
