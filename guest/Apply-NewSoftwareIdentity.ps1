#Requires -Version 5.1
param([switch]$Auto,[switch]$Restore,[switch]$RegisterTask,[switch]$ShowOnly,[switch]$Force)
$ErrorActionPreference='Stop'
$Root=Split-Path -Parent $MyInvocation.MyCommand.Path
$BackupFile=Join-Path $Root 'original_backup.json'
$FlagFile=Join-Path $Root 'identity_applied.flag'
$LogFile=Join-Path $Root 'operation_log.txt'
$TaskName='LabApplySoftwareIdentity'
function L($m){ $x=('{0}  {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'),$m); Add-Content $LogFile $x -Encoding UTF8; Write-Host $x }
function Assert-Admin {
  $p=New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
  if(-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){ throw '需要管理员权限' }
}
function RS($path,$name){ try{ (Get-ItemProperty -LiteralPath $path -Name $name -EA Stop).$name }catch{ $null } }
function WS($path,$name,$value){
  if(-not (Test-Path -LiteralPath $path)){ New-Item -Path $path -Force|Out-Null }
  New-ItemProperty -LiteralPath $path -Name $name -Value $value -PropertyType String -Force|Out-Null
}
function Show {
  Write-Host '======== 软件身份 ========' -ForegroundColor Green
  Write-Host ('MachineGuid : '+ (RS 'HKLM:\SOFTWARE\Microsoft\Cryptography' 'MachineGuid'))
  Write-Host ('SQM         : '+ (RS 'HKLM:\SOFTWARE\Microsoft\SQMClient' 'MachineId'))
  Write-Host ('HwProfile   : '+ (RS 'HKLM:\SYSTEM\CurrentControlSet\Control\IDConfigDB\Hardware Profiles\0001' 'HwProfileGuid'))
  Write-Host ('SusClientId : '+ (RS 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate' 'SusClientId'))
  Write-Host ('Computer    : '+ $env:COMPUTERNAME)
  try{
    $csp=Get-CimInstance Win32_ComputerSystemProduct
    Write-Host '======== 硬件身份(只读) ========' -ForegroundColor Cyan
    Write-Host ('SMBIOS UUID : '+ $csp.UUID)
    Write-Host ('Vendor/Name : '+ $csp.Vendor + ' / ' + $csp.Name)
    Write-Host ('Serial      : '+ $csp.IdentifyingNumber)
  } catch {}
}
function Backup {
  if(Test-Path $BackupFile){ L '已有 original_backup.json，不覆盖'; return }
  $o=[ordered]@{ kind='original_backup'; created_at=(Get-Date).ToString('o'); machine_guid=RS 'HKLM:\SOFTWARE\Microsoft\Cryptography' 'MachineGuid'; computer=$env:COMPUTERNAME }
  [IO.File]::WriteAllText($BackupFile,($o|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
  L '已写 original_backup.json'
}
function Apply {
  Backup
  $guid=[guid]::NewGuid().ToString()
  $sqm='{'+[guid]::NewGuid().ToString().ToUpper()+'}'
  $hwg='{'+[guid]::NewGuid().ToString().ToUpper()+'}'
  $sus=[guid]::NewGuid().ToString()
  $chars='ABCDEFGHJKLMNPQRSTUVWXYZ23456789'.ToCharArray()
  $name='DESKTOP-'+ -join ((1..7)|%{ $chars[(Get-Random -Max $chars.Length)] })
  L "新身份 $name $guid"
  WS 'HKLM:\SOFTWARE\Microsoft\Cryptography' 'MachineGuid' $guid
  WS 'HKLM:\SOFTWARE\Microsoft\SQMClient' 'MachineId' $sqm
  WS 'HKLM:\SYSTEM\CurrentControlSet\Control\IDConfigDB\Hardware Profiles\0001' 'HwProfileGuid' $hwg
  WS 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate' 'SusClientId' $sus
  Remove-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate' -Name SusClientIdValidation -EA SilentlyContinue
  try{ Rename-Computer -NewName $name -Force -EA Stop }catch{ L "主机名失败 $($_.Exception.Message)" }
  Set-Content $FlagFile (Get-Date).ToString('o') -Encoding UTF8
  L '软件层已应用，主机名可能需重启'
}
function Restore-Orig {
  if(-not (Test-Path $BackupFile)){ throw '没有 original_backup.json' }
  $b=Get-Content $BackupFile -Encoding UTF8 -Raw | ConvertFrom-Json
  if($b.machine_guid){ WS 'HKLM:\SOFTWARE\Microsoft\Cryptography' 'MachineGuid' $b.machine_guid }
  if($b.computer){ try{ Rename-Computer -NewName $b.computer -Force }catch{} }
  if(Test-Path $FlagFile){ Remove-Item $FlagFile -Force }
  L '已恢复，请重启'
}
function Register {
  $runner=Join-Path $Root '_task_run.bat'
  if(-not (Test-Path $runner)){ throw '找不到 _task_run.bat' }
  schtasks.exe /Create /TN $TaskName /TR "`"$runner`"" /SC ONSTART /RU SYSTEM /RL HIGHEST /F | Out-Null
  if($LASTEXITCODE -ne 0){ throw "注册计划任务失败 $LASTEXITCODE" }
  L "已注册开机任务 $TaskName"
}
try{
  Assert-Admin
  if($RegisterTask){ Register; return }
  if($ShowOnly){ Show; return }
  if($Restore){ Restore-Orig; return }
  if($Auto){
    if((Test-Path $FlagFile) -and -not $Force){ L 'flag 存在，跳过'; return }
    Apply; return
  }
  Show
}catch{ L "错误 $($_.Exception.Message)"; throw }
