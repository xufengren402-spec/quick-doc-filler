# Quick Doc Filler（快速文档填报与 GitHub 分析 APP）

基于 Flutter 构建的跨平台移动应用，支持微信/腾讯文档、飞书、金山文档（WPS）链接自动识别、个人档案本地加密预填充，以及基于官方 GitHub REST API 的开源项目搜索与质量评级。

## 零本地环境云端打包 APK 步骤（GitHub Actions）

1. 在 [GitHub](https://github.com/new) 新建一个仓库（例如 `quick-doc-filler`，可设为 Private 私有仓库）。
2. 解压本压缩包，将文件夹内的所有文件（注意包含 `.github` 隐藏文件夹）上传到该仓库根目录并提交到 `main` 分支。
3. 打开仓库顶部的 **Actions** 标签页，等待 **Build Android APK** 工作流自动运行完成（通常约 3～5 分钟，出现绿色对勾即成功）。
4. 点击该次运行记录，在页面底部的 **Artifacts** 区域点击 **`quick-doc-filler-apk`** 下载压缩包，解压后即可获得 `app-release.apk` 并传到安卓手机安装。

> 若未自动触发，可在 **Actions -> Build Android APK** 右侧点击 **Run workflow** 手动触发打包。
