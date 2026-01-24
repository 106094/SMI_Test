$usbroot="$modulepath\usbtool"
function getusbinfo([string]$filepath){
    $busfile=$filepath.replace(".log","_bus.log")
    $volfile=$filepath.replace(".log","_vol.log")
    $beforetime=get-date
    start-process "$usbroot\UsbDriveInfo.exe" -ArgumentList "-rb=$busfile"
    start-process "$usbroot\UsbDriveInfo.exe" -ArgumentList "-rv=$volfile"
    while (!(test-path $busfile) -or !(test-path $volfile)){
     start-sleep -s 1
    }
    while ($atime -lt $beforetime -and $btime -lt $beforetime){
        start-sleep -s 1
        $atime=(Get-ChildItem $busfile).LastWriteTime
        $btime=(Get-ChildItem $volfile).LastWriteTime
    }
}

function diskexplore([string]$type,[string]$picname){
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
if($type -eq "property"){
$ws.SendKeys("%{Enter}")
start-sleep -s 2
screenshot -picpath $picfolder -picname $picname
$ws.SendKeys("%{F4}")
start-sleep -s 1
}
$ws.SendKeys("%{F4}")
}

function diskmgnt([string]$type,[string]$picname){
    #diskmanagement
mmc.exe diskmgmt.msc
start-sleep -s 5
$proc = Get-Process mmc | Where-Object {
    $_.MainWindowTitle -like "*Disk Management*"
}
Get-Process -id  $proc.id | Set-WindowState -State MAXIMIZE
start-sleep -s 1
if($type -eq "partition_style"){
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
}
$proc.CloseMainWindow()
}

function cdm($ini,[string]$logname){
    if($ini.length -ne 0){
        #set up ini
    }
  $cdmexe="$usbroot\CrystalDiskMark\DiskMark64.exe"
  .$cdmexe
  start-sleep -s 5
  $noruntitle=(get-process -name diskmark64).MainWindowTitle
  $wclick=Get-AppWindowRect -ProcessName "diskmark64" -shiftpercentage -clickshiftX 10 -clickshiftY 2 
  $clickX=$wclick.ClickX
  $clickY=$wclick.ClickY
  [Clicker]::LeftClickAtPoint($clickX,$clickY)
   start-sleep -s 1
   $ws.SendKeys("{TAB}")
   start-sleep -s 1
   $ws.SendKeys(" ")
   $starttime=get-date
   start-sleep -s 5
    $diskwindowfinish=0
   while ($diskwindowfinish -lt 5){
   $diskwindowfinish=0
    for($i=0;$i -lt 5;$i++){
    start-sleep -s 1
    $diskwindowcheck=((get-process -name "diskmark64")|Where-Object{$_.MainWindowTitle -eq $noruntitle}).count
    $diskwindowfinish+=$diskwindowcheck
    }
   }
   $endttime=get-date
   $runningtime=(New-TimeSpan -start $starttime -end $endttime)
   $minutes = [int]$runningtime.TotalMinutes
   $seconds = $runningtime.Seconds
   $runtimeText = "{0}min {1}s" -f $minutes, $seconds
   write-output "DiskMark run test for $runtimeText"
   #save image and txt
   $timesuffix=get-date -format "_yyMMddHHmmss"
   $logpath="$logfolder\CrystalDiskMark"
    @(".txt", ".png")|ForEach-Object{
    $extension=$_
    $filename="$($logname)$($timesuffix)$($extension)"
    [Clicker]::LeftClickAtPoint($clickX,$clickY)
    Start-Sleep -Milliseconds 500
    if($_ -like "*.png"){
     $ws.SendKeys("^s")
     }
    else{
      $ws.SendKeys("^t")
    }
     Set-Clipboard -value $logpath     
    Start-Sleep -s 2
     $ws.SendKeys("^l")
    Start-Sleep -s 1
     $ws.SendKeys("^v")
    Start-Sleep -s 1
     $ws.SendKeys("~")
    Start-Sleep -s 2
    $lastfiles=Get-ChildItem $logpath|Where-Object{$_.name -like "*$extension"}
     $newfile=""
     $ws.SendKeys("%s")
     while(!$newfile){        
      Start-Sleep -s 1
      $newfiles=Get-ChildItem $logpath|Where-Object{$_.name -like "*$extension"}
      $newfile= $newfiles |Where-Object{$_.name -notin $lastfiles.name}
     }
    rename-item $newfile.FullName -NewName $filename
    }

}