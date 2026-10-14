# Codex Extension Fixer v1.0.0 — Liquid Glass

**原生 Windows 重写正式版**，采用 C# / .NET 10 / WPF，不再通过 PowerShell 脚本包装成 EXE。

## 下载安装

请下载下面的 **Codex-Extension-Fixer.exe**。这是 Windows x64 自包含单文件程序，运行时无须安装 .NET SDK、Node.js 或额外的 PowerShell 脚本。

从信任的 GitHub Release 页面下载后，建议用 PowerShell 校验：
```powershell
Get-FileHash .\Codex-Extension-Fixer.exe -Algorithm SHA256
```
哈希值应与 `Codex-Extension-Fixer.exe.sha256` 一致。

## 本版亮点

- **原创 Liquid Glass 风格：** 深蓝紫环境光、半透明玻璃卡片、柔和高光边缘、悬停反馈和细微动效。
- **原生窗口体验：** 支持最小化、最大化/还原、拖动标题栏及 Per-Monitor V2 DPI 感知。
- **完全重写修复核心：** 原生 C# 查找 Codex 安装目录和正式 Node 运行时；自动忽略不完整的 `.staging-*`。
- **默认安全检测：** 仅扫描已识别的浏览器扩展配置；只有用户明确确认后才修复。
- **备份与保护性恢复：** 原文件完整备份、SHA-256 校验、原子替换、避免覆盖官方更新后的配置。
- **本地离线：** 工具自身不上传配置或对话，不改变系统代理/TUN，不清理 Codex 数据。

## 使用方法

1. 打开 EXE，先点击「立即检测」。
2. 检测到可修复失效路径时，先彻底退出 Codex、Chrome 以及 Codex 更新程序。
3. 点击「备份并修复」并确认。
4. 重新启动 Codex 和浏览器扩展进行验证。如遇问题，可在条件允许时恢复最近的完整备份。

## 已执行的测试与边界

- ✅ GitHub Windows Runner：WPF 编译、C# 失效配置模拟修复/恢复测试、EXE 构建、PE 文件校验、窗口进程启动烟雾测试。
- ✅ 上一版原生界面已在真实 Windows 11 设备上确认可启动及只读检测。
- ⚠️ 本版视觉精修未经过真实设备的逐项高 DPI/动画人工验收；自动进程启动测试不等于完整人工 UI 测试。
- ⚠️ EXE 在**真实损坏的 Codex 安装环境**下执行修改和恢复的完整实机流程尚未验收；这些路径目前通过模拟测试。
- ⚠️ 仅修复已识别的 Chrome 扩展运行时路径问题，不保证修复登录、网络、WebSocket 或未来所有 Codex 配置格式。
- ⚠️ 当前未进行代码签名，Windows SmartScreen 可能提示「未知发布者」。请核对来源、哈希并自行判断是否运行。

## 项目说明

这是独立的社区开源工具，**不是 OpenAI 或 Apple 官方产品**。Liquid Glass 是原创 Windows 风格的视觉设计灵感，不实现苹果系统的真实折射引擎。

原有 [v0.2.0 PowerShell 版](https://github.com/lunalens-maker/Codex-Extension-Fixer/releases/tag/v0.2.0) 仍然保留，可作为兼容性回退版本。未来如 Codex 官方改变扩展清单结构，工具仍可能需要维护更新。
