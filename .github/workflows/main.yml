name: Build Android APK

on:
  push:
    branches: ["main", "master"]
  workflow_dispatch:

permissions:
  contents: write

jobs:
  build-apk:
    runs-on: ubuntu-latest
    steps:
      - name: 拉取代码
        uses: actions/checkout@v4

      - name: 配置 Java 17
        uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: "17"

      - name: 配置 Flutter Stable
        uses: subosito/flutter-action@v2
        with:
          channel: stable
          cache: true

      - name: 生成 Android 平台工程文件
        run: |
          if [ ! -d "android" ]; then
            flutter create --platforms=android --org com.quickdoc.filler --project-name quick_doc_filler .
            rm -f test/widget_test.dart
          fi

      - name: 补齐网络权限、minSdk >= 23 并关闭 Release Lint 阻塞
        run: |
          python3 - << 'EOF'
          from pathlib import Path
          import re

          manifest = Path("android/app/src/main/AndroidManifest.xml")
          if manifest.exists():
              text = manifest.read_text(encoding="utf-8")
              perm = '<uses-permission android:name="android.permission.INTERNET"/>'
              if "android.permission.INTERNET" not in text:
                  text = text.replace("<application", f"    {perm}\n    <application", 1)
                  manifest.write_text(text, encoding="utf-8")

          for gradle_name in ["android/app/build.gradle.kts", "android/app/build.gradle"]:
              gp = Path(gradle_name)
              if gp.exists():
                  gtext = gp.read_text(encoding="utf-8")
                  gtext = re.sub(r"minSdk\s*=\s*flutter\.minSdkVersion", "minSdk = 23", gtext)
                  gtext = re.sub(r"minSdkVersion\s+flutter\.minSdkVersion", "minSdkVersion 23", gtext)
                  gtext = re.sub(r"minSdk\s*=\s*21", "minSdk = 23", gtext)
                  gtext = re.sub(r"minSdkVersion\s+21", "minSdkVersion 23", gtext)
                  if "checkReleaseBuilds" not in gtext:
                      if gradle_name.endswith(".kts"):
                          lint_block = "android {\n    lint {\n        checkReleaseBuilds = false\n        abortOnError = false\n    }\n"
                      else:
                          lint_block = "android {\n    lint {\n        checkReleaseBuilds false\n        abortOnError false\n    }\n"
                      gtext = gtext.replace("android {", lint_block, 1)
                  gp.write_text(gtext, encoding="utf-8")
          EOF

      - name: 安装依赖
        run: flutter pub get

      - name: 运行单元测试
        run: flutter test

      - name: 编译 Release APK（注入当前构建号供应用内检查更新）
        run: |
          flutter build apk --release \
            --dart-define=APP_BUILD_NUMBER=${{ github.run_number }} \
            --dart-define=APP_VERSION=v2.3.${{ github.run_number }}

      - name: 按独立版本号重命名 APK
        run: |
          cp build/app/outputs/flutter-apk/app-release.apk "quick-doc-filler-v2.3.${{ github.run_number }}.apk"

      - name: 发布新版本到 Releases（不覆盖历史版本）
        uses: softprops/action-gh-release@v2
        with:
          tag_name: v2.3.${{ github.run_number }}
          name: 文档快填助手 v2.3.${{ github.run_number }}
          files: quick-doc-filler-v2.3.${{ github.run_number }}.apk
