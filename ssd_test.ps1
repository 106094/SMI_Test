Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy Bypass -Force
Add-Type -AssemblyName System.Windows.Forms,System.Drawing,Microsoft.VisualBasic
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type -AssemblyName PresentationFramework
$shell=New-Object -ComObject shell.application
$ws=New-Object -ComObject wscript.shell

$screen = [System.Windows.Forms.Screen]::PrimaryScreen
$bounds = $screen.Bounds
$screenheight=$bounds.Bottom
$screenwidth=$bounds.Right
if ($PSScriptRoot) {
    $rootpath = $PSScriptRoot
} else {
    $rootpath = [System.AppDomain]::CurrentDomain.BaseDirectory
}       
if(!$rootpath -or $rootpath -like "*system32*"){
    $rootpath="$env:userprofile\Desktop\Auto\SMI_Test_Win11"
}
$modulepath= (join-path $rootpath "modules").tostring()
$psroot="$modulepath\clicktool"
$usbroot="$modulepath\usbtool"
Import-Module $modulepath\functionmodules.psm1 -force
Import-Module $modulepath\actionmodules.psm1 -force
if (!(test-path $usbroot)){
Expand-Archive -Path $modulepath\usbtool.zip -DestinationPath $usbroot
}
$diskpath=get_driverletter
if($diskpath.Length -eq 0){
    exit
}
$driverletter=$($diskpath).replace(":","")
$logfolder = (join-path $rootpath "logs").tostring()
$logmain=(join-path $logfolder "all.log").tostring()
$picfolder = (join-path $logfolder "screenshots").tostring()
if(!(test-path $picfolder)){
new-item -itemtype directory $picfolder |Out-Null
}
$build = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -Name "CurrentBuild" | Select-Object -ExpandProperty CurrentBuild
Write-Output $ostype
if([int]$build -ge 22000){
$os="WIN11"
$settingpath="$modulepath\fs_cluster_sizes_win11.csv"
if(!(test-path $settingpath)){
    getsupportformatwin11
    $ws.Popup("Please check if need revise format settings!`n[fs_cluster_sizes_win11.csv] in $modulepath", 0, "System Alert", 48 + 0)|Out-Null
    exit
}
$selections=@(
    "[1] OS20:quick fomat (Fill file)",
    "[2] OS21:full fomat (without file)",
    "[3] OS21:full fomat (with 5G file)",
    "[4] OS93: 100G copying till disk filled"
)
if (!(test-path $psroot)){
Expand-Archive -Path $modulepath\clicktool.zip -DestinationPath $psroot
}
}
else{
$os="WIN10"
$settingpath="$modulepath\fs_cluster_sizes_win10.csv"
if(!(test-path $settingpath)){
getsupportformat
    $ws.Popup("Please check if need revise format settings!`n [fs_cluster_sizes_win10.csv] in $modulepath", 0, "System Alert", 48 + 0)|Out-Null
    exit
}
$selections=@(
    "[1] OS20:quick fomat (without file)",
    "[2] OS20:quick fomat (with 5G file)",
    "[3] OS21:full fomat (without file)",
    "[4] OS21:full fomat (with 5G file)",
    "[5] OS93: 100G copying till disk filled"
)
}

$options=wpfselections -selections $selections
$timesuffix=get-date -format "_yyMMdd-HHmmss"
$formatcsvlog=Join-Path $logfolder "$($os)_format$($timesuffix).csv"
<#skip
diskexploreaction -type "property" -picname "OS03-B"
diskmgnt -type "partition_style" -picname "OS03-D"
$file1024=test-FileSizeOnDisk 1024 -index "OS06-C" #OS06-C
$clustercheck=test_diskClusterSize -DeviceType "FLASH" -index "OS06-D" #OS06-D
#>
(get-process -name "ssd_test")| Set-WindowState -State MINIMIZE
if($os -match "11"){
if($options -like "*[[]1[]]*"){win11format -index "OS20Scen2_clean" -fillfile}
if($options -like "*[[]2[]]*"){win11format -index "OS21Scen2_clean" -nonquick}
if($options -like "*[[]3[]]*"){win11format -index "OS21Scen2_file" -withfile -nonquick}
}
else{
if($options -like "*[[]1[]]*"){win11format -index "OS20Scen1_clean"} #OS20 format
if($options -like "*[[]2[]]*"){win11format -index "OS20Scen1_file" -withfile } #OS20 with 5GB file copied before format
if($options -like "*[[]3[]]*"){win11format -index "OS21Scen1_clean" -nonquick } #OS21 full format
if($options -like "*[[]4[]]*"){win11format -index "OS21scen1_file" -withfile -nonquick} #OS21 with 5GB file copied before full format
}
if($options -like "*OS93*"){
OS93
}






<#
#get text info
$filesystem=(Get-Volume -DriveLetter $driverletter).FileSystem #OS03-C
$diskNumber = (Get-Partition -DriveLetter $driverletter).DiskNumber
$PartitionStyle=(Get-Disk -Number $diskNumber).PartitionStyle #OS03-E
#>
