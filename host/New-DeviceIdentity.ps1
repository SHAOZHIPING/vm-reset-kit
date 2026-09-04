#Requires -Version 5.1
param(
    [ValidateSet('Show','Snapshot','Restore','NewHardware','NewDevice')]
    [string]$Action='NewDevice',
    [string]$VmName='Windows 11 实验机',
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
    foreach($p in @("$env:ProgramFiles\Oracle\VirtualBox\VBoxManage.exe","${env:ProgramFiles(x86)}\Oracle\VirtualBox\VBoxManage.exe")){
        if($p -and (Test-Path -LiteralPath $p)){ return $p }
    }
    $f=Get-Command VBoxManage.exe -EA SilentlyContinue
    if($f){ return $f.Source }
    throw '找不到 VBoxManage.exe。请在宿主机运行。'
}
function VB([string[]]$a){
    $exe=Find-VBoxManage
    W Cyan ('[*] VBoxManage '+($a -join ' '))
    $o=& $exe @a 2>&1
    $t=($o|ForEach-Object{"$_"}) -join "`n"
    if($LASTEXITCODE -ne 0){ throw "VBoxManage 失败 $LASTEXITCODE $t" }
    return $t
}
function Info {
    $raw=VB @('showvminfo',$VmName,'--machinereadable')
    $m=[ordered]@{}
    foreach($line in ($raw -split "`r?`n")){
        $i=$line.IndexOf('=')
        if($i -lt 1){ continue }
        $k=$line.Substring(0,$i)
        $v=$line.Substring($i+1).Trim('"')
        $m[$k]=$v
    }
    if(-not $m.Contains('UUID')){ throw "读不到虚拟机 $VmName" }
    return $m
}
function Stop-Lab {
    $s=(Info)['VMState']; W Cyan "[*] $s"
    if($s -in @('poweroff','aborted')){ return }
    if($s -eq 'saved'){ VB @('discardstate',$VmName)|Out-Null; return }
    try{ VB @('controlvm',$VmName,'poweroff')|Out-Null }catch{}
    for($n=0;$n -lt 40;$n++){ Start-Sleep 1; if((Info)['VMState'] -in @('poweroff','aborted')){ Start-Sleep 1; return } }
    throw '关机超时'
}
function Rnd([int]$n=12){ $c='ABCDEFGHJKLMNPQRSTUVWXYZ23456789'.ToCharArray(); -join (1..$n|%{ $c[(Get-Random -Max $c.Length)] }) }
function Extra($k,$v){ VB @('setextradata',$VmName,$k,$v)|Out-Null }
function New-Hw {
    Stop-Lab
    $uuid=[guid]::NewGuid().ToString()
    $sys='LS'+(Rnd 10); $board='MB'+(Rnd 10); $disk=('LAB'+(Rnd 17)).Substring(0,20)
    $pairs=@{ DmiBIOSVendor='LabResearch BIOS'; DmiBIOSVersion='1.10'; DmiBIOSReleaseDate='06/15/2023'; DmiSystemVendor='LabResearch'; DmiSystemProduct='Experiment-Station'; DmiSystemVersion='1.0'; DmiSystemSerial=$sys; DmiSystemSKU='SKU-'+(Rnd 6); DmiSystemFamily='LabPC'; DmiSystemUuid=$uuid; DmiBoardVendor='LabResearch'; DmiBoardProduct='ES-MB-01'; DmiBoardVersion='A01'; DmiBoardSerial=$board; DmiChassisVendor='LabResearch'; DmiChassisSerial=('CH'+(Rnd 10)); DmiProcManufacturer='GenuineIntel'; DmiProcVersion='Intel(R) Core(TM) i7-11700'; DmiOEMVBoxVer='LabResearch_DMI' }
    foreach($root in @('VBoxInternal/Devices/pcbios/0/Config','VBoxInternal/Devices/efi/0/Config')){
        foreach($k in $pairs.Keys){ Extra "$root/$k" $pairs[$k] }
    }
    VB @('modifyvm',$VmName,'--hardwareuuid',$uuid)|Out-Null
    $info=Info
    Extra 'VBoxInternal/Devices/ahci/0/Config/Port0/SerialNumber' $disk
    Extra 'VBoxInternal/Devices/ahci/0/Config/Port0/ModelNumber' 'LAB-SSD-1TB'
    1..8|%{ $n=$_; if($info.Contains("nic$n") -and $info["nic$n"] -notin @('none','', $null)){ VB @('modifyvm',$VmName,"--macaddress$n",'auto')|Out-Null } }
    if(-not $SkipTpmRecreate){
        try{ VB @('modifyvm',$VmName,'--tpm-type','none')|Out-Null; Start-Sleep -Milliseconds 400; VB @('modifyvm',$VmName,'--tpm-type','2.0')|Out-Null }catch{}
    }
    $info2=Info; $macs=[ordered]@{}
    1..8|%{ if($info2.Contains("macaddress$_")){ $macs["nic$_"]=$info2["macaddress$_"] } }
    $rec=[ordered]@{ hardware_uuid=$uuid; sys_serial=$sys; disk_serial=$disk; mac=$macs }
    [IO.File]::WriteAllText($LastIdentityFile,($rec|ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
    W Green '[+] hardware identity saved'
    return $rec
}
function HasSnap { try{ $t=VB @('snapshot',$VmName,'list'); return ($t -match [regex]::Escape($SnapName)) }catch{ return $false } }
function TakeSnap {
    Stop-Lab
    if(HasSnap){ VB @('snapshot',$VmName,'delete',$SnapName)|Out-Null }
    VB @('snapshot',$VmName,'take',$SnapName,'--description','clean')|Out-Null
    W Green "[+] snapshot $SnapName"
}
function RestoreSnap {
    Stop-Lab
    if(-not (HasSnap)){ throw "no snapshot $SnapName" }
    VB @('snapshot',$VmName,'restore',$SnapName)|Out-Null
    W Green '[+] restored'
}
function NewDevice {
    if(-not $SkipSnapshotRestore){ if(HasSnap){ RestoreSnap } else { W Yellow '[!] no snapshot, hardware only' } }
    New-Hw|Out-Null
    VB @('startvm',$VmName)|Out-Null
    W Green '[+] started'
}
function Show { $i=Info; W White "VM=$VmName state=$($i['VMState']) uuid=$($i['UUID']) hw=$($i['hardwareuuid'])"; if(Test-Path $LastIdentityFile){ Get-Content $LastIdentityFile -Encoding UTF8 } }
try{
    W Cyan "Action=$Action VM=$VmName Snap=$SnapName"
    switch($Action){ 'Show'{Show}; 'Snapshot'{TakeSnap}; 'Restore'{RestoreSnap}; 'NewHardware'{New-Hw|ConvertTo-Json -Depth 5|Write-Host}; 'NewDevice'{NewDevice} }
    W Green '[+] done'; exit 0
}catch{ W Red "[x] $_"; exit 1 }
