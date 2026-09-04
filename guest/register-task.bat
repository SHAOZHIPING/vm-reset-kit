@echo off
cd /d "%~dp0"
net session >nul 2>&1
if errorlevel 1 (
  echo Need Administrator. Right-click this file and Run as administrator.
  pause
  exit /b 1
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Apply-NewSoftwareIdentity.ps1" -RegisterTask
echo.
pause
