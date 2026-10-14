# Codex Extension Fixer · Liquid Glass (native rewrite)

**开发分支**：`feature/native-liquid-glass-v1`

这是从旧版 PowerShell/WinForms/PS2EXE 到 **C# + .NET 10 WPF** 的完整桌面程序重写。旧版 `v0.2.0` 的 Release 和主分支仍保留，避免没有验证就覆盖已知可用版本。

## 外观

- 深色液态玻璃设计语言：柔和环境光、半透明多层卡片、亮边框、圆角胶囊、悬停反馈
- Windows 11：尝试启用系统 Mica / 深色窗口属性；其他环境使用渐变回退
- 原生 Windows 控件，不嵌入网页或下载在线 CSS/JS
- 自定义标题栏、现代化状态看板、Codex 版本/Node 运行时/异常字段三个状态卡

本界面是**受 Apple Liquid Glass 视觉语言启发的原创 Windows 设计**，不是 Apple 官方界面；WinUI/Acrylic 级实时背景折射不在 WPF 本身的原生能力范围内。

## 安全行为

- 默认仅扫描；仅定位浏览器扩展对应的 `entries` 配置
- 未找到正式完整的 Node 运行时，不使用 `.staging-*` 临时目录
- 未识别的 JSON 结构及非 Codex 运行时路径不会强行改写
- 修改前保存完整文件备份，修复使用原位原子替换
- 恢复前检查 SHA-256，避免覆盖 Codex 官方更新过的新配置
- 不上传诊断数据，不修改 Clash、代理、登录状态或用户对话
- 与旧版 PowerShell 工具使用兼容的 `backup-info.json` 基本字段格式

## 开发构建（Windows 10/11）

环境：.NET 10 SDK。

```powershell
dotnet build native/CodexExtensionFixer/CodexExtensionFixer.csproj -c Release
dotnet run --project tests/NativeTests/NativeTests.csproj -c Release
dotnet publish native/CodexExtensionFixer/CodexExtensionFixer.csproj -c Release -r win-x64 --self-contained true -o dist/native
```

GitHub Actions 在 Windows Runner 上执行完整构建、模拟损坏配置测试与单文件 EXE 打包：

[Native liquid-glass Windows build](https://github.com/lunalens-maker/Codex-Extension-Fixer/actions/workflows/native-build.yml)

**测试与发布原则**：通过 CI 只能证明构建与模拟测试成功，仍需要真实 Windows 电脑确认窗口显示、高 DPI、按钮行为和真实受损配置修复流程，之后才应将新版本发布为正式 Release。

## 仓库结构

```text
native/CodexExtensionFixer/
  App.xaml
  App.xaml.cs
  MainWindow.xaml
  MainWindow.xaml.cs
  FixerService.cs
  CodexExtensionFixer.csproj

tests/NativeTests/
  NativeTests.csproj
  Program.cs

.github/workflows/native-build.yml
```

旧版保留在仓库根目录，不影响历史 `v0.2.0` 下载。
