@echo off
chcp 65001 >nul
cd /d "%~dp0"
net session >nul 2>&1
if errorlevel 1 (
  echo 需要管理员。
  pause
  exit /b 1
)
echo ==========================================================
echo  可选高级操作：sysprep /generalize
echo ==========================================================
echo 只有当你的实验会采集「机器 SID」时才需要这一步。
echo 执行后虚拟机会关机并回到 OOBE。
echo 普通指纹实验不要跑这个。
echo.
pause
echo 5 秒后开始 sysprep，关闭本窗口可取消...
timeout /t 5
%WINDIR%\System32\Sysprep\sysprep.exe /generalize /oobe /shutdown /quiet
