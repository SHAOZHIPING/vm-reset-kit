#Requires -Version 5.1
param(
    [switch]$Auto,
    [switch]$Restore,
    [switch]$RegisterTask,
    [switch]$ShowOnly,
    [switch]$Force
)
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$BackupFile = Join-Path $Root 'original_backup.json'
$FlagFile = Join-Path $Root 'identity_applied.flag'
$LogFile = Join-Path $Root 'operation_log.txt'
$TaskName = 'LabApplySoftwareIdentity'

function L {
    param([string]$m)
    $x = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + '  ' + $m
    Add-Content -Path $LogFile -Value $x -Encoding UTF8
    Write-Host $x
}

function Assert-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object Security.Principal.WindowsPrincipal($id)
    if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Need Administrator'
    }
}

function RS {
    param($path, $name)
    try { (Get-ItemProperty -LiteralPath $path -Name $name -ErrorAction Stop).$name } catch { $null }
}

function WS {
    param($path, $name, $value)
    if (-not (Test-Path -LiteralPath $path)) { New-Item -Path $path -Force | Out-Null }
    New-ItemProperty -LiteralPath $path -Name $name -Value $value -PropertyType String -Force | Out-Null
}

function Show {
    Write-Host '==== software ====' -ForegroundColor Green
    Write-Host ('MachineGuid : ' + (RS 'HKLM:\SOFTWARE\Microsoft\Cryptography' 'MachineGuid'))
    Write-Host ('SQM         : ' + (RS 'HKLM:\SOFTWARE\Microsoft\SQMClient' 'MachineId'))
    Write-Host ('HwProfile   : ' + (RS 'HKLM:\SYSTEM\CurrentControlSet\Control\IDConfigDB\Hardware Profiles\0001' 'HwProfileGuid'))
    Write-Host ('SusClientId : ' + (RS 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate' 'SusClientId'))
    Write-Host ('Computer    : ' + $env:COMPUTERNAME)
    try {
        $csp = Get-CimInstance Win32_ComputerSystemProduct
        Write-Host '==== hardware (read-only) ====' -ForegroundColor Cyan
        Write-Host ('SMBIOS UUID : ' + $csp.UUID)
        Write-Host ('Vendor/Name : ' + $csp.Vendor + ' / ' + $csp.Name)
        Write-Host ('Serial      : ' + $csp.IdentifyingNumber)
    } catch {}
}

function Backup {
    if (Test-Path $BackupFile) { L 'backup exists'; return }
    $o = [ordered]@{
        kind         = 'original_backup'
        created_at   = (Get-Date).ToString('o')
        machine_guid = RS 'HKLM:\SOFTWARE\Microsoft\Cryptography' 'MachineGuid'
        computer     = $env:COMPUTERNAME
    }
    [IO.File]::WriteAllText($BackupFile, ($o | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
    L 'wrote original_backup.json'
}

function Apply {
    Backup
    $guid = [guid]::NewGuid().ToString()
    $sqm = '{' + [guid]::NewGuid().ToString().ToUpper() + '}'
    $hwg = '{' + [guid]::NewGuid().ToString().ToUpper() + '}'
    $sus = [guid]::NewGuid().ToString()
    $chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'.ToCharArray()
    $name = 'DESKTOP-' + (-join (1..7 | ForEach-Object { $chars[(Get-Random -Maximum $chars.Length)] }))
    L ('new identity ' + $name + ' ' + $guid)
    WS 'HKLM:\SOFTWARE\Microsoft\Cryptography' 'MachineGuid' $guid
    WS 'HKLM:\SOFTWARE\Microsoft\SQMClient' 'MachineId' $sqm
    WS 'HKLM:\SYSTEM\CurrentControlSet\Control\IDConfigDB\Hardware Profiles\0001' 'HwProfileGuid' $hwg
    WS 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate' 'SusClientId' $sus
    Remove-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate' -Name 'SusClientIdValidation' -ErrorAction SilentlyContinue
    try { Rename-Computer -NewName $name -Force -ErrorAction Stop } catch { L ('rename failed ' + $_.Exception.Message) }
    Set-Content -Path $FlagFile -Value ((Get-Date).ToString('o')) -Encoding UTF8
    L 'software identity applied'
}

function Restore-Orig {
    if (-not (Test-Path $BackupFile)) { throw 'no original_backup.json' }
    $b = Get-Content -Path $BackupFile -Encoding UTF8 -Raw | ConvertFrom-Json
    if ($b.machine_guid) { WS 'HKLM:\SOFTWARE\Microsoft\Cryptography' 'MachineGuid' $b.machine_guid }
    if ($b.computer) { try { Rename-Computer -NewName $b.computer -Force } catch {} }
    if (Test-Path $FlagFile) { Remove-Item $FlagFile -Force }
    L 'restored'
}

function Register {
    $runner = Join-Path $Root '_task_run.bat'
    if (-not (Test-Path $runner)) { throw 'missing _task_run.bat' }
    $tr = [char]34 + $runner + [char]34
    & schtasks.exe /Create /TN $TaskName /TR $tr /SC ONSTART /RU SYSTEM /RL HIGHEST /F | Out-Null
    if ($LASTEXITCODE -ne 0) { throw ('schtasks failed ' + $LASTEXITCODE) }
    L ('registered task ' + $TaskName)
}

Assert-Admin
if ($RegisterTask) { Register; exit 0 }
if ($ShowOnly) { Show; exit 0 }
if ($Restore) { Restore-Orig; exit 0 }
if ($Auto) {
    if ((Test-Path $FlagFile) -and (-not $Force)) { L 'flag exists, skip'; exit 0 }
    Apply
    exit 0
}
Show
