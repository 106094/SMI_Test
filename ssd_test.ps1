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
    $rootpath="$env:userprofile\Desktop\Auto"
}
$driverletter="D"
$modulepath="$rootpath\modules"
    Import-Module $modulepath\click.psm1 -force
    Import-Module $modulepath\functionmodules.psm1 -force
$picfolder = "$rootpath\logs\screenshots"
if(!(test-path $picfolder)){
new-item -itemtype directory $picfolder |Out-Null
}

#from disk property to check file system type (e.g. FAT32, NTFS, exFAT)
Start-Process explorer.exe -ArgumentList 'shell:MyComputerFolder' -WindowStyle Maximized
start-sleep -s 6
[Clicker]::LeftClickAtPoint($screenwidth/2, $screenheight/2)
start-sleep -s 1
$ws.SendKeys("^+7") #Tiles view
start-sleep -s 1
$ws.SendKeys(" ") 
start-sleep -s 1
$ws.SendKeys("{Right}")
start-sleep -s 1
$ws.SendKeys("%{Enter}")
start-sleep -s 2
screenshot -picpath $picfolder -picname "OS03-B"
$ws.SendKeys("%{F4}")
start-sleep -s 1
$ws.SendKeys("%{F4}")
#diskmanagement
mmc.exe diskmgmt.msc
start-sleep -s 3
$proc = Get-Process mmc | Where-Object {
    $_.MainWindowTitle -like "*Disk Management*"
}
Get-Process -id  $proc.id | Set-WindowState -State MAXIMIZE
start-sleep -s 1
$ws.SendKeys("{DOWN}")
start-sleep -Milliseconds 200
$ws.SendKeys("{DOWN}")
start-sleep -Milliseconds 200
$ws.SendKeys("{DOWN}")
start-sleep -Milliseconds 200
$ws.SendKeys("{DOWN}")
start-sleep -s 1
$ws.SendKeys("{LEFT}")
start-sleep -Milliseconds 500
$ws.SendKeys("+{F10}")
start-sleep -s 1
$ws.SendKeys("p")
start-sleep -s 1
$ws.SendKeys("+{TAB}")
start-sleep -Milliseconds 500
$ws.SendKeys("{RIGHT 2}")
screenshot -picpath $picfolder -picname "OS03-D"
$ws.SendKeys("%{F4}")
$proc.CloseMainWindow()
#get text info
$filesystem=(Get-Volume -DriveLetter $driverletter).FileSystem #OS03-C
$diskNumber = (Get-Partition -DriveLetter $driverletter).DiskNumber
$PartitionStyle=(Get-Disk -Number $diskNumber).PartitionStyle #OS03-E


$foldername="OS20"
$clicknames="b"
foreach($clickname in $clicknames){
click -imagef $clickname -foldername  $foldername
}


