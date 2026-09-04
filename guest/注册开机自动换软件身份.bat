@echo off
chcp 65001 >nul
cd /d "%~dp0"
net session >nul 2>&1
if errorlevel 1 (
  echo 需要管理员权限。请右键 → 以管理员身份运行。
  pause
  exit /b 1
)
echo 将注册开机任务 LabApplySoftwareIdentity：
echo  - 以 SYSTEM 在开机时运行
echo  - 若还没有 identity_applied.flag，就换一套新的软件身份
echo  - 拍快照之前运行本文件，然后关机，再在宿主机拍「实验干净起点」
echo  - 以后每次「还原快照 + 新硬件」开机，都会自动换软件身份一次
echo  - 实验过程中重启不会再改（flag 还在）
echo.
pause
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Apply-NewSoftwareIdentity.ps1" -RegisterTask
echo.
pause
