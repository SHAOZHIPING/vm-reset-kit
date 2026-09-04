@echo off
chcp 65001 >nul
cd /d "%~dp0"
echo ==========================================
echo  只还原快照（硬件身份也会回到拍照时）
echo ==========================================
echo 若要「还原系统 + 换成新硬件」，请用 2_一键变成新设备并开机.bat
echo.
pause
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0New-DeviceIdentity.ps1" -Action Restore
echo.
pause
