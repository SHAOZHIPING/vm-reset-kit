@echo off
chcp 65001 >nul
cd /d "%~dp0"
echo ==========================================
echo  只换虚拟硬件，不还原快照
echo ==========================================
echo 磁盘里的 Windows 软件身份（SID/MachineGuid 等）会保留。
echo 只适合已经在客户机里手动跑过软件换身份工具的情况。
echo.
pause
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0New-DeviceIdentity.ps1" -Action NewHardware
echo.
echo 需要的话请再手动开机。
pause
