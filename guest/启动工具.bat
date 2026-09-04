@echo off
chcp 65001 >nul
cd /d "%~dp0"
net session >nul 2>&1
if errorlevel 1 (
  echo 需要管理员权限。请右键本文件 → 以管理员身份运行。
  pause
  exit /b 1
)

where py >nul 2>&1
if %errorlevel%==0 (
  py -3 -c "import sys; raise SystemExit(0 if sys.maxsize>2**32 and sys.version_info>=(3,10) else 1)" 2>nul
  if not errorlevel 1 (
    py -3 "%~dp0device_fingerprint_tool.py"
    goto :eof
  )
)
where python >nul 2>&1
if %errorlevel%==0 (
  python -c "import sys; raise SystemExit(0 if sys.maxsize>2**32 and sys.version_info>=(3,10) else 1)" 2>nul
  if not errorlevel 1 (
    python "%~dp0device_fingerprint_tool.py"
    goto :eof
  )
)

echo 未检测到 64 位 Python 3.10+，改用 PowerShell 菜单（功能相同）。
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Apply-NewSoftwareIdentity.ps1" -ShowOnly
echo.
echo [1] 生成并应用新伪装设备配置
echo [2] 一键恢复原始真实设备
echo [3] 注册开机自动换身份（拍快照前做一次）
echo [4] 退出
choice /C 1234 /N /M "请选择："
if errorlevel 4 goto :eof
if errorlevel 3 (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Apply-NewSoftwareIdentity.ps1" -RegisterTask
  pause
  goto :eof
)
if errorlevel 2 (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Apply-NewSoftwareIdentity.ps1" -Restore
  pause
  goto :eof
)
if errorlevel 1 (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Apply-NewSoftwareIdentity.ps1" -Auto -Force
  pause
)
