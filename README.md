# Codex Extension Fixer 🛠️

**一款适用于 Windows 的开源小工具，用来检查和修复 Codex 桌面版更新后，Chrome 中 ChatGPT/Codex 扩展无法启动的失效路径。**

> **非官方项目**：本工具与 OpenAI 无隶属关系。它只修复本机配置引用，不绕过身份验证，不代替 Codex 官方更新程序。

## 症状

Chrome 扩展显示：

```text
Unable to start ChatGPT
Codex app-server manifest entry is missing required path nodePath
```

一种已确认的成因是：Codex 更新后，两个 `chrome-native-hosts-v2.json` 清单仍引用已被替换的 Node 运行时和旧版 `app/resources` 目录。**不是所有同名错误都由此导致**；本工具只处理能够检测出的路径故障。

## ✨ 功能

- 🖥️ **Windows 图形界面**：检测问题 / 备份并修复 / 恢复上次备份 / 打开备份目录。
- 🔍 **安全扫描**：默认只读，检查两个 v2 清单中的 `nodePath`、`nodeReplPath`、`nodeModuleDirs` 和 `resourcesPath`。
- 🧭 **自动定位**：通过已安装的 `OpenAI.Codex` 查找当前资源目录；只选择有 `node.exe`、`node_repl.exe` 和 `node_modules` 的正式 `cua_node` 目录。
- 🛡️ **保护配置**：忽略 `.staging-*` 临时目录，只操作识别出的浏览器扩展条目，保留未知字段和其他条目；写入前备份原始清单。
- ↩️ **带校验恢复**：只在文件自修复以来没有发生变化时自动恢复，防止覆盖 Codex 更新后的新配置。
- 📴 **离线工具**：无需管理员权限、无需安装 Python/Node/npm、不访问网络，也不上传任何文件。
- 🧪 **自动化测试**：包含离线模拟安装环境测试和 GitHub Actions 工作流。

## 下载 Windows EXE（v0.2.0 正式发布）

**[⬇️ 下载 Codex-Extension-Fixer.exe](https://github.com/lunalens-maker/Codex-Extension-Fixer/releases/download/v0.2.0/Codex-Extension-Fixer.exe)** · [完整 Release 说明](https://github.com/lunalens-maker/Codex-Extension-Fixer/releases/tag/v0.2.0) · [SHA-256 校验文件](https://github.com/lunalens-maker/Codex-Extension-Fixer/releases/download/v0.2.0/Codex-Extension-Fixer.exe.sha256)

下载后双击 `Codex-Extension-Fixer.exe`，先点击「检测问题」。只有确实发现失效路径时，才需要退出 Chrome 与 Codex 并确认备份后点击「备份并修复」。

本版 EXE 沿用 GitHub Actions 中**已实机验证能正常打开及只读扫描**的构建产物，SHA-256：

```text
2BA5894CA118C7FF20F9EF8905435C80B7B4D02E11FD875EBE0EBF227F3A1464
```

**测试范围：** Windows 图形界面启动、运行时识别及只读扫描已通过实机验证；修复与恢复功能通过隔离的自动化模拟测试，但尚未完成真实受损安装的 EXE 修复/恢复端到端测试。EXE 依赖 Windows 自带的 PowerShell/.NET 运行组件；它没有代码签名，因此可能出现 SmartScreen「未知发布者」警告。请确认下载来源并校验文件哈希后再运行。

### 开发者自动构建

`main` 分支推送后，GitHub Actions 会运行测试，并用 [PS2EXE](https://github.com/MScholtes/PS2EXE) 1.0.18 编译。开发预览版可在 [Build Windows EXE Actions](https://github.com/lunalens-maker/Codex-Extension-Fixer/actions/workflows/build-exe.yml) 的 Artifacts 下载；正式用户推荐使用上方 Release 附件。编译过程会安装 PS2EXE，生成的修复工具自身不联网或上传配置。

## 快速使用（Windows 11 / Windows 10）

1. 从 GitHub 仓库右上角 **Code → Download ZIP** 获取源码，并解压整个文件夹。不要只下载一个 `.ps1` 文件。
2. 双击 **`Start.cmd`**，打开工具界面。
3. 点击 **检测问题**。如果显示有可修复项，先**正常退出 Chrome 和 Codex（包括后台进程）**。
4. 点击 **备份并修复**，阅读确认提示后选择“是”。
5. 重新启动 Codex 和 Chrome，打开浏览器扩展验证。

启动脚本仅对该 PowerShell 子进程使用 `-ExecutionPolicy Bypass`，**不会改变电脑的系统执行策略**。只运行可信来源的脚本，下载后建议查看源码。

> **注意**：如果检测不到完整正式运行时，工具不会从 `.staging-*` 临时文件夹随意拷贝 Node。请通过官方 Codex 客户端修复/完成更新，再检测。

## 命令行用法（可选）

在项目文件夹打开 PowerShell：

```powershell
# 只检查（默认操作）
powershell.exe -NoProfile -File .\Fix-Codex.ps1 -Action Scan

# 先关闭 Chrome 和 Codex，再执行修复（需明确确认）
powershell.exe -NoProfile -File .\Fix-Codex.ps1 -Action Repair -Yes

# 恢复最近一次完整备份（仅当文件未被后来更新时可用）
powershell.exe -NoProfile -File .\Fix-Codex.ps1 -Action Restore -Yes
```

如果系统脚本执行策略阻止运行，可以改用 `Start.cmd`；命令行也可以明确添加 `-ExecutionPolicy Bypass`，仅作用于当次进程。

## 修改哪些文件？

| 目标 | 作用 |
|---|---|
| `%LOCALAPPDATA%\OpenAI\Codex\chrome-native-hosts-v2.json` | Codex AppData 里的扩展清单 |
| `%USERPROFILE%\.codex\chrome-native-hosts-v2.json` | 用户目录里的扩展清单 |

需要修复时会在 **`%LOCALAPPDATA%\Codex-Extension-Fixer\Backups`** 备份原始完整文件，并记录 SHA-256 校验。不会直接删除 `.codex` 目录、历史对话、登录数据、插件或 MCP 设置。

修复是**根据当前可用版本重写失效引用**，不创建 Windows 定时任务，不后台常驻，也不更改 TUN/Clash 代理模式。

## 排查与限制

- 工具检查的是 **Chrome 扩展运行时路径**。Codex 桌面版偶发 WebSocket `open_timeout`、网络代理问题，是另一类故障，本工具不保证解决。
- 如果浏览器扩展版本与本机 Codex 桌面版不兼容，或底层注册表 Native Messaging Host 注册错误，可能需要另外排查。
- 如果 Codex 官方更新改变了清单结构，工具会跳过不认识的结构，不强行写入。
- 如果目标配置正被其他进程占用，修复可能失败；请关闭浏览器和 Codex 后重试。
- 更新过程中不要同时运行修复工具。建议等 Codex 更新完全结束再使用。
- 如果恢复时检测到新版本已改动清单，工具会**拒绝覆盖**。备份仍在本机，可用于人工排查。
- `Backup` 中可能包含本地配置路径及其他用户信息，请不要上传备份文件或带个人路径的诊断日志到公开仓库。

## 开发和测试

目录结构：

```text
Codex-Extension-Fixer/
├── Start.cmd                       # PowerShell 版本双击启动
├── Codex-Fixer.ps1                   # WinForms 图形界面
├── Fix-Codex.ps1                   # 命令行
├── src/CodexFixer.Core.ps1         # 检测、备份、修复、恢复逻辑
├── tests/Run-Tests.ps1             # 使用临时模拟环境的离线测试
├── build/Build-Exe.ps1             # 合并源码并生成单文件 EXE
├── .gitignore                      # Git 忽略规则
├── .github/workflows/ci.yml       # Windows 核心测试
└── .github/workflows/build-exe.yml # EXE 自动构建
```

在 Windows PowerShell 中运行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Run-Tests.ps1
```

测试只使用系统临时目录，不触碰真实 Codex 安装。

要在 Windows 本地构建 EXE（需要网络获取编译依赖）：

```powershell
Install-Module -Name ps2exe -RequiredVersion 1.0.18 -Scope CurrentUser -Force
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\build\Build-Exe.ps1
```

生成文件位于 `dist/Codex-Extension-Fixer.exe`；不要把编译输出目录提交到仓库。

## 发布到 GitHub

此文件夹本身就是一个完整的 GitHub 仓库结构，包括 README、LICENSE、忽略文件、测试脚本和 CI。

### 网页上传（不需要安装 Git）

1. 登录 GitHub，点击右上角 `+` → **New repository**。
2. 推荐仓库名：`Codex-Extension-Fixer`，公开或私有均可；不用勾选自动创建 README / License，因为项目已经带了。
3. 创建仓库后，在仓库页面选择 **uploading an existing file**，**上传解压后的项目文件与目录**（不要只上传 ZIP），提交即可。
4. 可在 **Actions** 页面查看 Windows 测试。首次发布前最好在自己的 Windows 电脑执行一次 `tests/Run-Tests.ps1`。

### Git 命令行上传（可选）

```powershell
git init
git add .
git commit -m "feat: initial Codex Extension Fixer"
git branch -M main
git remote add origin https://github.com/<YOUR_USERNAME>/Codex-Extension-Fixer.git
git push -u origin main
```

先在 GitHub 创建空仓库，替换 `<YOUR_USERNAME>` 后再执行命令。不要上传个人电脑的原始 JSON 清单、诊断日志或本地备份。

## 开源协议

[MIT License](LICENSE)。欢迎通过 Issue 反馈新的清单结构和错误信息（发布前请删除个人目录、令牌等隐私信息）。
