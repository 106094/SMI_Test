Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy Bypass -Force
  Add-Type -AssemblyName System.Windows.Forms,System.Drawing,Microsoft.VisualBasic
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
$logfolder="$rootpath\logs"
$picfolder = "$logfolder\screenshots"
if(!(test-path $picfolder)){
new-item -itemtype directory $picfolder |Out-Null
}
$resultlogs=@()


diskexplore -type "property" -picname "OS03-B"
diskmgnt -type "partition_style" -picname "OS03-D"
test-FileSizeOnDisk 1024 -index "OS06-C" #OS06-C
test_diskClusterSize -DeviceType "FLASH" -index "OS06-D" #OS06-D
$drive = Get-PSDrive -Name $driverletter
$used  = $drive.Used
$free  = $drive.Free
$total = $used + $free
Get-CimInstance Win32_Volume |
Where-Object {
    $_.FileSystem -eq 'NTFS' -and $_.DriveLetter -like "$driverletter*"
} |
ForEach-Object {
    $clusterKB = $_.BlockSize / 1KB
    [PSCustomObject]@{
        Drive       = $_.DriveLetter
        FileSystem  = $_.FileSystem
        used        = $used
        free        = $free
        total       = $total
        ClusterKB   = $clusterKB
        Status      = if ($clusterKB -eq 4) { 'PASS' } else { 'FLAG_NON_DEFAULT' }
    }
}

#get text info
$filesystem=(Get-Volume -DriveLetter $driverletter).FileSystem #OS03-C
$diskNumber = (Get-Partition -DriveLetter $driverletter).DiskNumber
$PartitionStyle=(Get-Disk -Number $diskNumber).PartitionStyle #OS03-E
$resultlogs+=[PSCustomObject]@{
    Device=""
    Environment=""
    TestName = ""
    step=""
    value=""
    Result=""
}

$foldername="OS20"
$clicknames="b"
foreach($clickname in $clicknames){
click -imagef $clickname -foldername  $foldername
}


