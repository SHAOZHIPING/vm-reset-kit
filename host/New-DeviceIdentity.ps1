#Requires -Version 5.1
param(
    [ValidateSet('Show','Snapshot','Restore','NewHardware','NewDevice')]
    [string]$Action='NewDevice',
    [string]$VmName='当前请保持为 Windows 11 实验机'.Replace('当前请保持为 ',''),
    [string]$SnapName='实验干净起点',
    [switch]$SkipSnapshotRestore,
    [switch]$SkipTpmRecreate
)
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=[Text.Encoding]::UTF8
$ScriptDir=Split-Path -Parent $MyInvocation.MyCommand.Path
$LastIdentityFile=Join-Path $ScriptDir 'last_identity.json'
function W($c,$m){ Write-Host $m -ForegroundColor $c }
function Find-VBoxManage {
    foreach($p in @(
        "$env:ProgramFiles\Oracle\VirtualBox\VBoxManage.exe",
        "${env:ProgramFiles(x86)}\Oracle\VirtualBox\VBoxManage.exe"
    )){ if($p -and (Test-Path -LiteralPath $p)){ return $p } }
    $f=Get-Command VBoxManage.exe -ErrorAction SilentlyContinue
    if($f){ return $f.Source }
    throw '找不到 VBoxManage.exe。请在宿主机（装了 VirtualBox 的电脑）运行。'
}
function VB([string[]]$a){
    $exe=Find-VBoxManage
    W Cyan ("[*] VBoxManage "+($a -join ' '))
    $o=& $exe @a 2>&1
    $t=($o|ForEach-Object{"$_"}) -join "`n"
    if($LASTEXITCODE -ne 0){ throw "VBoxManage 失败 ($LASTEXITCODE)：$t" }
    return $t
}
function Info {
    $raw=VB @('showvminfo',$VmName,'--machinereadable')
    $m=[ordered]@{}
    foreach($line in ($raw -split "`r?`n")){
        if($line -match '^([^=]+=\"(.*)\"$')){ }
        if($line -match '^([^=]+)=\"(.*)\"$'){ $m[$matches[1]]=$matches[2] }
        elseif($line -match '^([^=]+)=(.*)$'){ $m[$matches[1]]=$matches[2] }
    }
    if(-not $m.Contains('UUID')){ throw "读不到虚拟机「$VmName」，请核对名称。" }
    return $m
}
function Stop-Lab {
    $s=(Info)['VMState']; W Cyan "[*] 状态 $s"
    if($s -in @('poweroff','aborted')){ return }
    if($s -eq 'saved'){ VB @('discardstate',$VmName)|Out-Null; return }
    try{ VB @('controlvm',$VmName,'poweroff')|Out-Null }catch{}
    for($n=0;$n -lt 40;$n++){
        Start-Sleep 1
        if((Info)['VMState'] -in @('poweroff','aborted')){ Start-Sleep 1; return }
    }
    throw '关机超时'
}
function Rnd([int]$n=12){ $c='ABCDEFGHJKLMNPQRSTUVWXYZ23456789'.ToCharArray(); -join (1..$n|%{ $c[(Get-Random -Max $c.Length)] }) }
function Extra($k,$v){ VB @('setextradata',$VmName,$k,$v)|Out-Null }
function New-Hw {
    Stop-Lab
    $uuid=[guid]::NewGuid().ToString()
    $sys='LS'+ (Rnd 10); $board='MB'+(Rnd 10); $ch='CH'+(Rnd 10); $disk=('LAB'+(Rnd 17)).Substring(0,20)
    $pairs=@{
        DmiBIOSVendor='LabResearch BIOS'; DmiBIOSVersion='1.10'; DmiBIOSReleaseDate='06/15/2023'
        DmiSystemVendor='LabResearch'; DmiSystemProduct='Experiment-Station'; DmiSystemVersion='1.0'
        DmiSystemSerial=$sys; DmiSystemSKU='SKU-'+(Rnd 6); DmiSystemFamily='LabPC'; DmiSystemUuid=$uuid
        DmiBoardVendor='LabResearch'; DmiBoardProduct='ES-MB-01'; DmiBoardVersion='A01'; DmiBoardSerial=$board
        DmiBoardAssetTag='ASSET-'+(Rnd 6); DmiBoardLocInChass='Default string'
        DmiChassisVendor='LabResearch'; DmiChassisVersion='N/A'; DmiChassisSerial=$ch; DmiChassisAssetTag='CASE-'+(Rnd 6)
        DmiProcManufacturer='GenuineIntel'; DmiProcVersion='Intel(R) Core(TM) i7-11700 CPU @ 2.50GHz'
        DmiOEMVBoxVer='LabResearch_DMI'; DmiOEMVBoxRev=('rev_'+(Rnd 8))
    }
    $bytes=@{ DmiBIOSReleaseMajor='2'; DmiBIOSReleaseMinor='1'; DmiBIOSFirmwareMajor='2'; DmiBIOSFirmwareMinor='1'; DmiBoardBoardType='10'; DmiChassisType='3' }
    foreach($root in @('VBoxInternal/Devices/pcbios/0/Config','VBoxInternal/Devices/efi/0/Config')){
        foreach($k in $pairs.Keys){ Extra "$root/$k" $pairs[$k] }
        foreach($k in $bytes.Keys){ Extra "$root/$k" $bytes[$k] }
    }
    VB @('modifyvm',$VmName,'--hardwareuuid',$uuid)|Out-Null
    $info=Info
    $paths=@()
    $types=@(); foreach($k in $info.Keys){ if($k -match '^storagecontrollertype'){ $types+=$info[$k] } }
    if($types -match 'AHCI|ahci|IntelAhci'){ 0..3|%{ $paths+="VBoxInternal/Devices/ahci/0/Config/Port$_" } }
    if($types -match 'NVMe|nvme'){ $paths+='VBoxInternal/Devices/nvme/0/Config/Port0' }
    if($paths.Count -eq 0){ $paths=@('VBoxInternal/Devices/ahci/0/Config/Port0') }
    foreach($p in $paths){ Extra "$p/SerialNumber" $disk; Extra "$p/FirmwareRevision" ('L'+(Get-Random -Min 1000 -Max 9999)); Extra "$p/ModelNumber" 'LAB-SSD-1TB' }
    1..8|%{
        $n=$_
        if($info.Contains("nic$n") -and $info["nic$n"] -notin @('none','null','')){
            VB @('modifyvm',$VmName,"--macaddress$n",'auto')|Out-Null
        }
    }
    $tpm='skipped'
    if(-not $SkipTpmRecreate){
        try{ VB @('modifyvm',$VmName,'--tpm-type','none')|Out-Null; Start-Sleep -Milliseconds 400; VB @('modifyvm',$VmName,'--tpm-type','2.0')|Out-Null; $tpm='recreated-2.0' }
        catch{ try{ VB @('modifyvm',$VmName,'--tpm-type','v2.0')|Out-Null; $tpm='recreated-v2.0' }catch{ $tpm='failed'; W Yellow '[!] TPM 重建失败' } }
    }
    $info2=Info; $macs=[ordered]@{}
    1..8|%{ if($info2.Contains("macaddress$_") -and $info2["nic$_"] -notin @('none','null','')){ $macs["nic$_"]=$info2["macaddress$_"] } }
    $rec=[ordered]@{ created_at=(Get-Date).ToString('o'); hardware_uuid=$uuid; sys_serial=$sys; board_serial=$board; disk_serial=$disk; mac=$macs; tpm=$tpm }
    [IO.File]::WriteAllText($LastIdentityFile,($rec|ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
    W Green '[+] 新硬件身份已写入 last_identity.json'
    return $rec
}
function HasSnap {
    try{ $t=VB @('snapshot',$VmName,'list','--machinereadable') }catch{ return $false }
    return ($t -match [regex]::Escape($SnapName))
}
function TakeSnap {
    Stop-Lab
    if(HasSnap){ W Yellow "[!] 删除旧快照 $SnapName"; VB @('snapshot',$VmName,'delete',$SnapName)|Out-Null }
    VB @('snapshot',$VmName,'take',$SnapName,'--description','实验干净起点')|Out-Null
    W Green "[+] 快照已创建 $SnapName"
}
function RestoreSnap {
    Stop-Lab
    if(-not (HasSnap)){ throw "没有快照 $SnapName。请先运行 1_拍干净快照.bat" }
    VB @('snapshot',$VmName,'restore',$SnapName)|Out-Null
    W Green "[+] 已还原 $SnapName"
}
function NewDevice {
    if(-not $SkipSnapshotRestore){
        if(HasSnap){ RestoreSnap } else { W Yellow '[¡] 还没有快照，本次只换硬件' }
    }
    New-Hw|Out-Null
    VB @('startvm',$VmName)|Out-Null
    W Green '[¡] 已开机。登录后开机任务会换软件身份。'
}
function Show {
    $i=Info
    W White "VM=$VmName state=$($i['VMState']) uuid=$($i['UUID']) hw=$($i['hardwareuuid'])"
    1..4|%{ if($i["nic$_"] -and $i["nic$_"] -ne 'none'){ W White ("NIC{0} {1} {2}" -f $_,$i["macaddress$_"],$i["nic$_"]) } }
    if(Test-Path $LastIdentityFile){ Get-Content $LastIdentityFile -Encoding UTF8 }
}
try{
    W Cyan "动作=$Action  虚拟机=$VmName  快照=$SnapName"
    switch($Action){
        'Show'{ Show }
        'Snapshot'{ TakeSnap }
        'Restore'{ RestoreSnap }
        'NewHardware'{ New-Hw | ConvertTo-Json -Depth 5 | Write-Host }
        'NewDevice'{ NewDevice }
    }
    W Green '[¡] 完成'; exit 0
}catch{ W Red "[x] $_"; exit 1 }
