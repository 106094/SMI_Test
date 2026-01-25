Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy Bypass -Force
  Add-Type -AssemblyName System.Windows.Forms,System.Drawing,Microsoft.VisualBasic
  Add-Type -AssemblyName UIAutomationClient
  Add-Type -AssemblyName UIAutomationTypes
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
    $rootpath="$env:userprofile\Desktop\Main\SMI_Test"
}
$driverletter="D"
$modulepath="$rootpath\modules"
Import-Module $modulepath\functionmodules.psm1 -force
Import-Module $modulepath\actionmodules.psm1 -force
$logfolder="$rootpath\logs"
$picfolder = "$logfolder\screenshots"
if(!(test-path $picfolder)){
new-item -itemtype directory $picfolder |Out-Null
}
$resultlogs=@()
$script:formatresult=@()
diskexploreaction -type "property" -picname "OS03-B"
diskmgnt -type "partition_style" -picname "OS03-D"
$file1024=test-FileSizeOnDisk 1024 -index "OS06-C" #OS06-C
$clustercheck=test_diskClusterSize -DeviceType "FLASH" -index "OS06-D" #OS06-D

diskexploreaction -type "format" -index "OS20_clean" #OS20 format
diskexploreaction -type "format" -formatfile -formatfilesize 5GB -index "OS20_file" #OS20 with 5GB file copied before format

#get text info
$filesystem=(Get-Volume -DriveLetter $driverletter).FileSystem #OS03-C
$diskNumber = (Get-Partition -DriveLetter $driverletter).DiskNumber
$PartitionStyle=(Get-Disk -Number $diskNumber).PartitionStyle #OS03-E

$foldername="OS20"
$clicknames="b"
foreach($clickname in $clicknames){
click -imagef $clickname -foldername  $foldername
}


