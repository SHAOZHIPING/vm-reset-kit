@echo off
chcp 65001 >nul
cd /d "%~dp0"
echo ==========================================
echo  一键变成另一台设备并开机
echo ==========================================
echo 将执行：
echo  1. 关机
echo  2. 还原快照「实验干净起点」（若存在）
echo  3. 随机化 SMBIOS UUID / 主板序列号 / 磁盘序列号 / MAC / 虚拟TPM
echo  4. 开机
echo  5. 客户机开机任务再换软件层身份
echo.
echo 不会改：宿主机物理 TPM、物理硬盘固件、BitLocker 开关、机器 SID
echo        （SID 要全新请走 sysprep 黄金镜像，见 README）
echo.
pause
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0New-DeviceIdentity.ps1" -Action NewDevice
echo.
pause
