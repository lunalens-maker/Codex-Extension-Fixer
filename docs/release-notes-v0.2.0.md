# Codex Extension Fixer v0.2.0

首个提供 **Windows x64 单文件 EXE** 的公开版本。

## 下载与使用

下载本页面 **Assets** 中的 `Codex-Extension-Fixer.exe`（不要下载源码 ZIP 代替 EXE）。双击启动后，先点击「检测问题」；只有检测到可修复的失效路径时，才需要关闭 Chrome 和 Codex 后手动点击「备份并修复」。

无需额外下载 Node.js 或 PowerShell 项目源码；程序仍依赖 Windows 的 PowerShell/.NET 运行组件。

## 主要功能

- 自动检测 Codex Windows 更新后 Chrome 扩展 `nodePath`、`nodeReplPath`、`nodeModuleDirs` 和 `resourcesPath` 的失效引用。
- 识别正式的完整 Node 运行时，避开 `.staging-*` 临时目录。
- 默认只读扫描，确认后才会备份并修改浏览器扩展清单。
- 修改前备份并校验文件哈希；恢复时防止覆盖被新版本更新的配置。
- 离线运行，不上传配置，不改变 Clash/TUN 分流设置，也不主动删除历史对话、插件或登录数据。

## 验证与限制

- **已通过** GitHub Actions 的 Windows PowerShell 5.1 隔离自动化测试、EXE 编译及 PE/版本信息检查。
- **已在 Windows 实机确认** EXE 能启动图形界面、识别 Codex 版本及运行时，并完成只读检测。
- **尚未在真实损坏的 Codex 安装中完成 EXE 修复与恢复全流程实机验证**；相应逻辑已通过模拟环境测试。
- 本工具仅修复能识别的 Chrome 扩展运行时路径问题，不保证解决所有登录、代理、WebSocket 或浏览器集成故障。
- 这是独立社区工具，**不是 OpenAI 官方产品**。EXE 尚未代码签名，Windows SmartScreen 可能提示“未知发布者”；请验证来源和 SHA-256 后谨慎决定是否运行。

## 文件校验

本版本提供 `Codex-Extension-Fixer.exe.sha256`，可在 Windows PowerShell 执行：

```powershell
Get-FileHash .\Codex-Extension-Fixer.exe -Algorithm SHA256
```

应与 SHA-256 校验文件及本页附件对应。正式发布附件沿用已完成实机启动测试的 GitHub Actions 构建产物。
