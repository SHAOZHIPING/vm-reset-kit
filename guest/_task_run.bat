@echo off
REM 计划任务入口：不要手动双击。实验中途重启时若已有 flag 会自动跳过。
cd /d "%~dp0"
"%WINDIR%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0Apply-NewSoftwareIdentity.ps1" -Auto
