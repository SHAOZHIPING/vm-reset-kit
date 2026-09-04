@echo off
chcp 65001 >nul
cd /d "%~dp0"
echo ==========================================
echo  拍摄干净快照：实验干净起点
echo ==========================================
echo 请先确认：
echo  1. 已经在虚拟机里走完 OOBE、建好本地账户
echo  2. 已经拷入 guest 目录并运行「注册开机自动换软件身份.bat」
echo  3. 虚拟机已关机（脚本也会强制关机）
echo  4. 还没有点过「变成新设备」（快照里应是原始软件身份）
echo.
pause
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0New-DeviceIdentity.ps1" -Action Snapshot
echo.
pause
