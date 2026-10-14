# Changelog

## v0.2.0（预览构建，尚未发布 Release）

- 使用 PS2EXE 1.0.18 合并图形界面与核心逻辑并构建 Windows x64 单文件 EXE。
- GitHub Actions 自动运行测试、校验 PE 文件并上传可下载 Artifact。
- 保留 Windows PowerShell 源码启动方式和保护性备份/恢复。

## v0.1.0 — 2026-10-14

- 初版 Windows 图形界面与 PowerShell 命令行。
- 自动识别当前 Codex Appx 资源目录与完整正式 Node 运行时。
- 检测并修复两份浏览器 Native Host v2 配置中的失效路径。
- 修复前备份、SHA-256 检查与保护性恢复。
- 离线临时目录集成测试与 GitHub Actions。
