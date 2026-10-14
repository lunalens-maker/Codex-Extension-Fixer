@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0LunaLens-Codex-Fixer.ps1"
if errorlevel 1 (
  echo.
  echo LunaLens Codex Fixer failed to start. Please check Windows PowerShell.
  pause
)
endlocal
