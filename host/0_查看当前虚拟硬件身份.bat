@echo off
chcp 65001 >nul
cd /d "%~dp0"
echo ==========================================
echo  查看 VirtualBox 当前虚拟硬件身份
echo ==========================================
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0New-DeviceIdentity.ps1" -Action Show
echo.
pause
