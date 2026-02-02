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
function diskexploropen([string]$openpath,[switch]$disk){
Start-Process explorer.exe -ArgumentList $openpath -WindowStyle Maximized
start-sleep -s 20
[Clicker]::LeftClickAtPoint($screenwidth/2, $screenheight/2)
start-sleep -s 1
$ws.SendKeys("^+7") #Tiles view
start-sleep -s 1
$ws.SendKeys(" ") 
start-sleep -s 1
if($disk){
for($i=0;$i -lt 20;$i++){
$ws.SendKeys("{Right}")  #select to right most (Disk)
start-sleep -Milliseconds 200
}
}
}
function diskexploreaction{
  param(
    [string]$type,
    [string]$picname,
    [switch]$withfile,
    [switch]$nonquick,
    [string]$index
  )
#from disk property to check file system type (e.g. FAT32, NTFS, exFAT)
$picfolder=(join-path $picfolder $index).tostring()
if($type -eq "property"){
diskexploropen -openpath "shell:MyComputerFolder" -disk
start-sleep -s 1
$ws.SendKeys("%{Enter}")
start-sleep -s 2
screenshot -picpath $picfolder -picname $picname
$ws.SendKeys("%{F4}")
start-sleep -s 1
$ws.SendKeys("%{F4}")
}
if($type -eq "format"){
 $timesuffix=get-date -format "_yyMMdd-HHmmss"
 $logfilename= "$($index)$($timesuffix).log"
 $logpath= (join-path $logfolder $logfilename).ToString()
 $copytakes="-"
 $matrix=import-csv $settingpath
 $types=$matrix.FileSystem|Get-Unique
 $skipcomb=@()
if($withfile){
    $matrix|Where-Object{$_."skip_withfile" -ne ""}|ForEach-Object{
    $skipcomb+= "$($_."FileSystem")$($_."AllocationUnitSize"))"
     }
   }
   else{
    $matrix|Where-Object{$_."skip_nofile" -ne ""}|ForEach-Object{
     $skipcomb+= "$($_."FileSystem")$($_."AllocationUnitSize"))"
    }
   }

if($withfile){
  #region create 5GB file
    outlog "format with file"
    $formatfilesize=5GB
    if($formatfilesize -ge 1GB){
        $filename="$($formatfilesize/1GB)GB"
    }
    elseif($formatfilesize -ge 1MB){
        $filename="$($formatfilesize/1MB)MB"
    }
    $filefull=(join-path $logfolder "$($filename).bin").ToString()
    if(!(test-path $filefull)){
    $formatfilebytes=[int64]$formatfilesize.ToString()
    fsutil file createNew $filefull $formatfilebytes
    outlog "$filefull create done"
    }
    Format-Volume -DriveLetter "$($driverletter)" -FileSystem exFAT -AllocationUnitSize 16384 -Force
    #endregion
}
#open file explore to focus the disk
diskexploropen -openpath "shell:MyComputerFolder" -disk

#decide which file sys/alllocate to run
foreach($type in $types){
$downselect1=$types.indexof($type)+1
$unitsizes=$matrix|Where-Object{$_.fileSystem -eq $type}
 foreach($unitsiz in $unitsizes){
    $unitsizbyte=$unitsiz."AllocationUnitSize"
    $settingcomb="$($type)$($unitsizbyte)"
    if($settingcomb -in $skipcomb){
        continue
    }
    $downselect2=$unitsizes.indexof($unitsiz)+1
    $unitsizstring="{0} bytes" -f $unitsizbyte
    if ([int64]$unitsizbyte -ge 1KB) {
    $unitsizstring = "{0} KB" -f ($unitsizbyte/ 1KB)
    }
   write-output "filesystem:$($type), alllocation unit size:$($unitsizstring)"
   $settingcombstring= "$($type)_$($unitsizstring)"
   $picnamestart="$($index)_$($settingcombstring)_Format_start"
    $picnamecomplete="$($index)_$($settingcombstring)_Format_complete"
   if($withfile){
   if(!(test-path $filefull)){
    fsutil file createnew $filefull $formatfilebytes|Out-Null
    }
    $dest = "$driverletter`:\"
    $sw = [Diagnostics.Stopwatch]::StartNew()
    Copy-Item -Path $filefull -Destination $dest -Force -ErrorAction SilentlyContinue
    $sw.Stop()
    $copytakes="$([math]::Round($sw.Elapsed.TotalSeconds,2)) sec"
    $minutes = [int]$sw.Elapsed.TotalMinutes
    $seconds = [int] $sw.Elapsed.Seconds
    $totalsecs = $runningtime.TotalSeconds
    $copytakes = "{0}min {1}s" -f $minutes, $seconds
    }
    $ws.SendKeys("{F5}")
    start-sleep -s 2
    #cdm test before formating
    $cdm_before=cdm -logname "$($index)_$($settingcombstring)_CDMTestbefore"
    $freebefore = "{0:N2}" -f $((Get-PSDrive -Name $driverletter).Free)
    $ws.SendKeys("+{F10}")
    start-sleep -s 2
    $ws.SendKeys("a")
    #file sys select
    start-sleep -s 1
    $ws.SendKeys("%f")
    start-sleep -s 1
        for ($j=0;$j -lt 5;$j++){
        $ws.SendKeys("{UP}") #reset to top one
        start-sleep -Milliseconds 500
        }
    for($x=1;$x -lt $downselect1;$x++){
        $ws.SendKeys("{Down}")
        Start-Sleep -Milliseconds 500
    }
    $ws.SendKeys("%a")
    start-sleep -s 1
    $ws.SendKeys("d") #reset to top one
    start-sleep -Milliseconds 500
    for($x=0;$x -lt $downselect2;$x++){
            $ws.SendKeys("{Down}")
            Start-Sleep -Milliseconds 500
    }
    if($nonquick){
    $ws.SendKeys("%o")
    start-sleep -s 1
    $ws.SendKeys(" ")
    start-sleep -s 1
    }
   screenshot -picpath $picfolder -picname "$($index)_$($settingcombstring)_settings"
    #start
    $ws.SendKeys("%s")
    #check warning
    $poptext=""
    while( !($poptext -like "*click OK*")){
    $poptext=(Get-PopupWindowText -TitleRegex 'Format').text
    start-sleep -Milliseconds 100
        }
    $ws.SendKeys(" ")
    $starttime=get-date
    #check complete
    $poptext=""
    while(!($poptext -like "*Complete*")){
    $poptext=(Get-PopupWindowText -TitleRegex 'Format').text
    start-sleep -Milliseconds 100
        }
    $endttime=get-date
    Start-Sleep -s 1
    screenshot -picpath $picfolder -picname "$($index)_$($settingcombstring)_Complete"
    $ws.SendKeys(" ") #close format window
    start-sleep -s 1
    #cdm test before formating
    $cdm_after=cdm -logname "$($index)_$($settingcombstring)_CDMTest_after"
    $freeafter = "{0:N2}" -f $((Get-PSDrive -Name $driverletter).Free)
    $runningtime=(New-TimeSpan -start $starttime -end $endttime)
    $minutes = [int]($runningtime.TotalMinutes)
    $seconds = [math]::round($runningtime.TotalSeconds % 60,2)
    $totalsecs =[math]::round($runningtime.TotalSeconds,2 )
    $runtimeText = "{0}min {1}s" -f $minutes, $seconds
    $formattime = "$($totalsecs)s ($($runtimeText))"
    outlog "format tooks: $runtimeText"
    $vol = Get-Volume -DriveLetter $driverletter
    $actualFS       = $vol.FileSystem
    $actualCluster  = $vol.AllocationUnitSize
    $actualalll  = "{0} bytes" -f ($actualCluster)
    if ($actualCluster -ge 15KB) {
    $actualalll = "{0} kilibytes" -f ($actualCluster/ 1KB)
    }
    $sizeGB = [math]::Round($vol.Size / 1GB,2)
    $driverpath="$($driverletter):"
    $logtime=get-date -format "yy/MM/dd HH:mm:ss"
    $formatresult=[PSCustomObject]@{
    Drive              = $driverpath
    FileSystem         = $actualFS
    AllocationUnitSize = $actualalll
    formattime         = $formattime
    VolumeSize_GB      = $sizeGB
    diskfree_Before    = $freebefore
    diskfree_After     = $freeafter
    CDM_Read_Before    = $cdm_before[0]
    CDM_Write_Before   = $cdm_before[1]
    CDM_Read_After     = $cdm_after[0]
    CDM_Write_After    = $cdm_after[1]
    Criteria           = "TBD"
    Result             = "OK"
    Index              = $index
    logtime            = $logtime
    }
$formatresult|export-csv -Path $formatcsvlog -Encoding UTF8 -NoTypeInformation -Append
$ws.SendKeys("%{F4}") #close file explore
start-sleep -s 1
}
$run++
}
$ws.SendKeys("%{F4}")
start-sleep -s 1
}
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
#reset view to disk

$ws.SendKeys("%")
start-sleep -Milliseconds 500
$ws.SendKeys("v")
start-sleep -Milliseconds 500
$ws.SendKeys("o")
start-sleep -Milliseconds 500
$ws.SendKeys("d")
start-sleep -Milliseconds 500

if($type -eq "partition_style"){
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

function cdm([string]$logname){
   $checkrun= get-process -name diskmark64 -ea SilentlyContinue
    if($checkrun){
      $checkrun.CloseMainWindow()
    }
   #ini file reviced
   $inipath="$usbroot\CrystalDiskMark\DiskMark64.ini"
   $inifile=get-content $inipath
    $newcontent=foreach($line in $inifile){
    if($line -match "TestCount\="){
        $line="TestCount=4" #5 times
    }
    if($line -match "TestSize\="){
        $line="TestSize=6" #1GiB
    }
      if($line -match "Benchmark\="){
        $line="Benchmark=3"  #read+write
    }
    $line
    }
set-content $inipath -value $newcontent -Force
(get-process -name "SystemSettings")| Set-WindowState -State MINIMIZE
  $checkos=get-process -name SystemSettings -ErrorAction SilentlyContinue
  if($checkos){
  [Win32User32]::ShowWindowAsync($checkos.MainWindowHandle, 6)|Out-Null
  }

$extracts=@()
  $cdmexe="$usbroot\CrystalDiskMark\DiskMark64.exe"
    .$cdmexe
  start-sleep -s 5
  $proc = Get-Process -Name DiskMark64
  [Win32User32]::ShowWindowAsync($proc.MainWindowHandle, 6)|Out-Null
   start-sleep -s 1
  [Win32User32]::ShowWindowAsync($proc.MainWindowHandle, 9)|Out-Null
   start-sleep -s 1
  [Win32User32]::SetForegroundWindow($proc.MainWindowHandle)|Out-Null
  start-sleep -s 1
  $noruntitle=(get-process -name diskmark64).MainWindowTitle
  $wclick=Get-AppWindowRect -ProcessName "diskmark64" -shiftpercentage -clickshiftX 10 -clickshiftY 2 
  $clickX=$wclick.ClickX
  $clickY=$wclick.ClickY
  [Clicker]::LeftClickAtPoint($clickX,$clickY)
   start-sleep -s 1
   for($i = 0;$i -lt 6; $i++){
   $ws.SendKeys("{TAB}")
   start-sleep -s 1
   if($i -eq 3){
   $ws.SendKeys($driverletter)
   start-sleep -s 1
   }
   }
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
   #$minutes = [int]$runningtime.TotalMinutes
   #$seconds = $runningtime.Seconds
   #$runtimeText = "{0}min {1}s" -f $minutes, $seconds
   #write-output "DiskMark run test for $runtimeText"
   #save image and txt
   $timesuffix=get-date -format "_yyMMddHHmmss"
   $logpath="$logfolder\CrystalDiskMark"
   if(!(test-path $logpath)){
    new-item -ItemType Directory -Path $logpath|Out-Null
   }
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
    #get read/write 
    if($filename -match ".txt"){
        $filefull=(join-path $logpath $filename).ToString()
        $contentlog = get-content $filefull
        $x=99
        foreach($logline in $contentlog){
           if($logline -match "\[Read\]"){
            $x=0
           } 
           if($logline -match "\[Write\]"){
            $x=0
           }
           if($x -eq 1){
            $extract=((($logline -split ":")[1] -split "\[")[0]).Trim()
            $extracts+=$extract
           }
           $x++
        }

    }
    }
  
  (get-process -name diskmark64).CloseMainWindow()|Out-Null
  $checkos=get-process -name SystemSettings -ErrorAction SilentlyContinue
  if($checkos){
  [Win32User32]::ShowWindowAsync($checkos.MainWindowHandle, 9)|Out-Null
   start-sleep -s 1
  [Win32User32]::SetForegroundWindow($checkos.MainWindowHandle) |Out-Null
  start-sleep -s 1
  }
  return $extracts
}

function test-FileSizeOnDisk {
    param(
        [Parameter(Mandatory)]
        [int]$xbypes,
        [string]$index
    )
    $Path="$($driverletter):\filename.txt"
    remove-item $Path -ErrorAction SilentlyContinue
    $formatfilebytes=[int64]$formatfilesize.ToString()
    fsutil file createnew $Path $formatfilebytes|out-null
    $file = Get-Item $Path
    $vol = Get-CimInstance Win32_Volume -Filter "DriveLetter='$($driverletter):'"
    # expected allocation
    #$clusterSize = $vol.BlockSize
    $fileSize = $file.Length

    $result =
        if ($fileSize -eq $xbypes ) {
            'PASS'
        }
        else{
            'FAIL'
        }

    [PSCustomObject]@{
        File                 = $file.Name
        FileSize_Bytes       = $fileSize
        Result               = $result
        Index                = $index
    }
}
function test_diskClusterSize {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('FLASH','SSD')]
        [string]$DeviceType,
        [string]$index
    )

    $vol = Get-CimInstance Win32_Volume -Filter "DriveLetter='$($driverletter):'"
    if (-not $vol) { throw "Drive $($driverletter) not found" }

    $clusterKB = $vol.BlockSize / 1KB
    $sizeGB = [math]::Round($vol.Capacity / 1GB)

    # ---- expected cluster size ----
    if ($DeviceType -eq 'SSD') {
        $expectedKB = 1024
    }
    else {
        $expectedKB = switch ($sizeGB) {
            { $_ -le 32 }   { 16; break }
            { $_ -le 256 }  { 32; break }
            { $_ -le 1024 } { 64; break }
            default         { 'UNKNOWN' }
        }
    }

    # ---- judgement ----
    $result =
        if ($expectedKB -eq 'UNKNOWN') {
            'FAIL_UNKNOWN_CAPACITY'
        }
        elseif ($clusterKB -eq $expectedKB) {
            'PASS'
        }
        else {
            'FAIL_CLUSTER_SIZE_MISMATCH'
        }

    $logtime=get-date -format "yy/MM/dd HH:mm:ss"
    [PSCustomObject]@{
        Drive          = "$($driverletter):"
        DeviceType     = $DeviceType
        Capacity_GB    = $sizeGB
        ClusterSize_KB = $clusterKB
        Expected_KB    = $expectedKB
        Result         = $result
        Index          = $index
        logtime        = $logtime
    }
}


function Get-FsMatrixGuiLike {

    $vol = Get-Volume -DriveLetter $driverletter -ErrorAction Stop
    $sizeGB = $vol.Size / 1GB

    $matrix = @{}
    $ntfsKB = @(0.5, 1, 2, 4, 8, 16, 32, 64, 128, 256, 512, 1024, 2048)
    $matrix['NTFS'] = $ntfsKB | ForEach-Object { [int]($_ * 1024) }   # bytes

    # ---- exFAT (common valid set) ----
    $exfatKB = @(4, 8, 16, 32, 64, 128, 256, 512, 1024, 2048)
    $matrix['exFAT'] = $exfatKB | ForEach-Object { $_ * 1024 }

    # ---- FAT32 (Windows format support is limited; keep realistic) ----
    # FAT32 on large volumes often blocked by Windows tools.
    if ($sizeGB -le 2048) {
        $fat32KB = @(4, 8, 16, 32, 64)
        $matrix['FAT32'] = $fat32KB | ForEach-Object { $_ * 1024 }
    }

    return $matrix
}
function FileCreate {
    param(
        [Parameter(Mandatory, ParameterSetName='BySize')]
        [Int64]$SizeBytes,
        [Parameter(ParameterSetName='FillDisk')]
        [switch]$FillDisk,
        [Parameter(ParameterSetName='FillDisk')]
        [string]$FileName = 'fsutil_test.bin',
        [string]$Filepath,
        [int64]$leftsize
    )
       
    if($Filepath.Length -eq 0){
         $Filepath="$($driverletter)`:"
    }
    $path = Join-Path $Filepath $FileName
    Remove-Item  $path -Force -ErrorAction SilentlyContinue
    $diskfreebefore=(Get-PSDrive -Name $driverletter).Free
    $diskusedbefore=(Get-PSDrive -Name $driverletter).Used
    $Size_MB="$([math]::Round($filelength / 1MB,2)) MB"
        if($FillDisk){
        format "$($driverletter):" /FS:NTFS /V:Test /Q /X /Y |out-null
        start-sleep -s 5
        $SizeBytes=$diskfreebefore - $leftsize
        }
        $fs = [System.IO.File]::Open( $path,'Create','Write','None')
        $fs.SetLength($SizeBytes)
        $fs.Close()
    # verify result
    $filelength=(get-childitem $Filepath).length
    if($filelength -eq $SizeBytes){
         $result="PASS"
    }
    else{
        $result="FAIL"
    }
    $diskfreeafter=(Get-PSDrive -Name $driverletter).Free
    $diskusedafter=(Get-PSDrive -Name $driverletter).Used
    $Size_MB="$([math]::Round($filelength / 1MB,2)) MB"
    $sizeafter="$($filelength) ($($Size_MB))"
    #$Size_GB="$([math]::Round($f.Length/ 1GB,2)) GB"
    $fscheck=[PSCustomObject]@{
        FilePath     = $path
        fsutilsize   = $SizeBytes
        FileSize     = $sizeafter
        Drive        = "$($driverletter):"
        result         = $result
        DiskUsed_Before  = $diskusedbefore
        DiskUsed_After   = $diskusedafter
        DiskFree_Before  = $diskfreebefore
        DiskFree_After   = $diskfreeafter
    }
    return $fscheck
}

function getdiskinfo([string]$index){
    $drive = Get-PSDrive -Name $driverletter
    $used  = $drive.Used
    $free  = $drive.Free
    $total = $used + $free
    $logtime=get-date -format "yy/MM/dd HH:mm:ss"
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
            Index       = $index
            logtime     = $logtime
        }
    }
}

function OS93{
    param(
    [int64]$totalsize=100GB
    )
$os93result=@()
$sublogfolder=(join-path $logfolder "OS93\CopyFrom").ToString()
    if(!(test-path $sublogfolder)){
        new-item -ItemType Directory -Path $sublogfolder|Out-Null
    }
    else{
        remove-item $sublogfolder -r -Force
    }
$picfoldersub="$picfolder\OS93"
$starttime=get-date -format "_yyMMdd-HHmmss"
$os93log="$logfolder\OS93$($starttime).log"
$partsize=$totalsize/20
for($i=1;$i -le 20;$i++){
    $blockname="Part_$("{0:D2}" -f $i).BIN"
    $filefullname=(Join-Path $sublogfolder $blockname).ToString()
    fsutil file createnew $filefullname $partsize|out-null
}
   $destpath="$($driverletter):" 
   remove-item "$destpath\*" -r -Force #clean disk
   
$x=1
$sw = [Diagnostics.Stopwatch]::StartNew()
while($true){
    $copyfolder="CopyTo-$("{0:D2}" -f $x)"
    $newdes="$($destpath)\$($copyfolder)"
    new-item -itemtype directory -path $newdes|out-null
    $destpath="$($driverletter):" 
    diskexploropen -openpath $sublogfolder
    start-sleep -s 5
    $ws.SendKeys(" ")
    start-sleep -s 1
    $ws.SendKeys("^a") 
    start-sleep -s 1
    $ws.SendKeys("^c")
    start-sleep -s 1
    diskexploropen -openpath $newdes
    start-sleep -s 5
    $ws.SendKeys(" ")
    start-sleep -s 1
    $ws.SendKeys("^v")
    $sw2 = [Diagnostics.Stopwatch]::StartNew()
    outlog -message "Round $($x) -Copy file starting" -logpath $os93log
    #wait 5 sec to see if alarm
    start-sleep -s 5
    screenshot -picpath $picfoldersub -picname $copyfolder
    $poptext1=(Get-PopupWindowText -TitleRegex 'complete').text
    $poptext2=(Get-PopupWindowText -TitleRegex 'interrupted').text
    if($poptext2 -like "*not enough*"){
    screenshot -picpath $picfoldersub -picname "drive_Filled"
    $ws.SendKeys("%c")   
    start-sleep -s 1
    $ws.SendKeys(" ")
    start-sleep -s 1
    $ws.SendKeys("%{F4}")
    start-sleep -s 1
    $ws.SendKeys("%{F4}")
    break
    }
    while($poptext1 -like "*copying*"){
    $poptext1=(Get-PopupWindowText -TitleRegex 'complete').text
    start-sleep -s 30
    }
    $copytakes="$([math]::Round($sw2.Elapsed.TotalSeconds,2)) sec"
    outlog -message "Copying Completed, idle for 20 min..." -logpath $os93log
    start-sleep -s 1200 #idle 20 mins
    #region comparefile
    $failhash=@()
    $failsize=@()
    $destfiles=Get-ChildItem $destfolders -file
     foreach ($destfiles in $destfiles){
         $fromfile=(join-path $sublogfolder $destfiles.Name).ToSingle()
         $fromfilehash=Get-FileHash -Path $fromfile -Algorithm SHA256
         $destfilehash=Get-FileHash -Path $destfiles.FullName -Algorithm SHA256
         $fromfilesize=(Get-ChildItem -Path $fromfile).Length
         $destfilesize= (Get-ChildItem -Path $destfiles.FullName).Length
         if($fromfilehash -ne $destfilehash){
           $failhash+=@($destfiles.FullName)
         }
         if($fromfilesize -ne $destfilesize){
           $failsize+=@($destfiles.FullName)
         }
        }
            $result="PASS"
            $failitems=@()
        if ($failsize){
            $result="NG"
            $failitems+=@("Size Fail",$($failsize -join "\")) -join ":"
        }
        if ($failhash){
            $result="NG"
            $failitems+=@("Hash Fail",$($failhash -join "\")) -join ":"
        }
        $failitems = ($failitems |Out-String).trim()
         $os93result+=[PSCustomObject]@{
            foldername = $newdes
            result     = $result
            failitems  = $failitems
            takingtime = $copytakes
         }
     
    $sw2.stop()
    $sw2.reset()
    #endregion
    $x++
    #close 2 file explore window
    start-sleep -s 1
    $ws.SendKeys("%{F4}")
    start-sleep -s 1
    $ws.SendKeys("%{F4}")
     }
$sw.stop()
$filltakes="$([math]::Round($sw.Elapsed.TotalSeconds,2)) sec"
outlog -message "total copying time: $($filltakes)" -logpath $os93log
    $datetime=get-date -format "_yyMMdd-HHmmss"
    $csvname="OS93_result$( $datetime).csv"
    $resultcsv=(join-path $logfolder $csvname).ToString()
    $os93result|export-csv $resultcsv -Encoding UTF8 -NoTypeInformation
   }

   function poweraction([string]$powertype,[int64]$count){
   #$currenttime=Get-Date -Format "yy/MM/dd HH:mm:ss"
   #$recordpath=join-path $logfolder "power.csv"
   $checkcount=0
   if(test-path $recordpath){
    $checkcount=(import-csv $recordpath|Where-Object{$_.type -eq $powertype}|Sort-Object -last 1).count
   }
    if($checkcount -lt $count){
        $checkcount++
        outlog "$powertype $checkcount"
        $datetime=Get-Date -Format "yy/MM/dd HH:mm:ss"
        $record=[PSCustomObject]@{
            powertype = $powertype
            count = $checkcount
            starting = $datetime
        }
        $record|export-csv $recordpath -Encoding UTF8 -NoTypeInformation
        start-sleep -s 60
       if($powertype -eq "HS3"){
        #judge if contains Hybrid sleep function and turn it on
       }
       if($powertype -eq "sleep"){
        #judge if contains Hybrid sleep function and turn it off

       }
        if($powertype -eq "reboot"){
    
       }
       if($powertype -eq "CB"){
    
       }
        if($powertype -eq "reboot"){
    
       }
    }
   }


  function outlog([string]$message,[string]$logpath){
    if($logpath.length -eq 0){
        $logpath=$logmain
    }
    $logtime=get-date -format "yy/MM/dd HH:mm:ss"
    $logmessage= "[$($logtime)]$($message)"
    if(!(test-path $logpath)){
        new-item $logpath -force|out-null
    }
    add-content $logpath -Value $logmessage -Force
  }

function testos{
$build = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -Name "CurrentBuild" | Select-Object -ExpandProperty CurrentBuild

if ([int]$build -ge 22000) {
   return "Win11"
} else {
   return "Win10"
}
}

function win11format_java([string]$index,[switch]$nonquick,[switch]$withfile){
installjava
downloadsikuli
$foldername="WIN11"
$clickname="format"
$picfolder=(join-path $picfolder $index).tostring()
$matrix=import-csv $settingpath
$types=$matrix.FileSystem|Get-Unique
$javalog="$modulepath\clicktool\SikuliLog_*.log"
$skipcomb=@()
if($withfile){
    $matrix|Where-Object{$_."skip_withfile" -ne ""}|ForEach-Object{
    $skipcomb+= "$($_."FileSystem")$($_."Support"))"
    }
   }
   else{
     $matrix|Where-Object{$_."skip_nofile" -ne ""}|ForEach-Object{
     $skipcomb+= "$($_."FileSystem")$($_."Support"))"
    }
   }
if($withfile){
  #region create 5GB file
    outlog "format with file"
    $formatfilesize=5GB
    if($formatfilesize -ge 1GB){
        $filename="$($formatfilesize/1GB)GB"
    }
    elseif($formatfilesize -ge 1MB){
        $filename="$($formatfilesize/1MB)MB"
    }
    $filefull=(join-path $logfolder "$($filename).bin").ToString()
    if(!(test-path $filefull)){
    $formatfilebytes=[int64]$formatfilesize.ToString()
    fsutil file createNew $filefull $formatfilebytes
    outlog "$filefull create done"
    }
    #endregion
}
if($fillfile -or $withfile){
    Format-Volume -DriveLetter "$($driverletter)" -FileSystem exFAT -AllocationUnitSize 16384 -Force
}
foreach($type in $types){
    $downselect1=$types.indexof($type)+1
    $unitsizes=($matrix|Where-Object{$_.FileSystem -eq $type}).Support
    foreach($unitsiz in $unitsizes){
        $settingcomb="$($type)$($unitsiz)"
        if($settingcomb -in $skipcomb){
            continue
        }
        $downselect2=$unitsizes.indexof($unitsiz)+1
        $unitsizstring="{0} bytes" -f $unitsiz
        if ([int64]$unitsiz -ge 1KB) {
        $unitsizstring = "{0} KB" -f ($unitsiz/ 1KB)
        }
        $picnamestart="$($type)_$($unitsizstring)_Format_start"
        $picnamecomplete="$($type)_$($unitsizstring)_Format_complete"
       #region copyfile 
       if($withfile){
            if(!(test-path $filefull)){
            fsutil file createnew $filefull $formatfilebytes|Out-Null
            }
        $dest = "$driverletter`:\"
        $sw = [Diagnostics.Stopwatch]::StartNew()
        Copy-Item -Path $filefull -Destination $dest -Force -ErrorAction SilentlyContinue
        $sw.Stop()
        $copytakes="$([math]::Round($sw.Elapsed.TotalSeconds,2)) sec"
        $minutes = [int]$sw.Elapsed.TotalMinutes
        $seconds = [int] $sw.Elapsed.Seconds
        $totalsecs = $runningtime.TotalSeconds
        $copytakes = "{0}min {1}s" -f $minutes, $seconds
        }
        #endregion
        $freebefore = "{0:N2}" -f $((Get-PSDrive -Name $driverletter).Free)
        #cdm test before formating
        $cdm_before=cdm -logname "$($index)_$($type)_$($unitsizstring)_CDMTestbefore"
        click -foldername $foldername -imagef $clickname -pyfile "click.py" -passkey "CLICK on"
        #save format time
        $ws.SendKeys("{TAB}")
        Start-Sleep -Milliseconds 500
        #select fiile system
        #reset to top
        for($x=1;$x -le 5;$x++){
            $ws.SendKeys("{UP}")
            Start-Sleep -Milliseconds 200
        }
        #select
        for($x=1;$x -lt $downselect1;$x++){
            $ws.SendKeys("{Down}")
            Start-Sleep -Milliseconds 500
        }
        $ws.SendKeys("{TAB}")
        Start-Sleep -Milliseconds 500
        #reset to top
        for($x=1;$x -le 20;$x++){
            $ws.SendKeys("{UP}")
            Start-Sleep -Milliseconds 200
        }
        #select alllocated unit size
        for($x=1;$x -lt $downselect2;$x++){
            $ws.SendKeys("{Down}")
            Start-Sleep -Milliseconds 500
        }
        if([int64]$unitsiz -lt 8000){
        $ws.SendKeys("{TAB}")
        Start-Sleep -Milliseconds 500
        }
        $ws.SendKeys("{TAB}")
        Start-Sleep -Milliseconds 500
        if($nonquick){
        $ws.SendKeys(" ")
        Start-Sleep -Milliseconds 500
        }
        $ws.SendKeys("{TAB}")
        screenshot -picpath $picfolder -picname $picnamestart
        outlog "start format [$type]-[$unitsizstring]"
        click -foldername $foldername -imagef $clickname -pyfile "click2.py" -passkey "elapsed time"
        screenshot -picpath $picfolder -picname $picnamecomplete
       # $ws.SendKeys("{Enter}")
       # Start-Sleep -s 5
       # $ws.SendKeys("{Enter}")
        $javalogfull=Get-ChildItem -path $javalog|Sort-Object LastWriteTime|Select-Object -last 1
        $javalogcontent=get-content $javalogfull.FullName
        $total = 0
       $javalogcontent | ForEach-Object {
            if ($_ -match 'doFindImage: end (\d+) msec') {
                $total += [int]$matches[1]
            }
            if ($_ -match 'doFindImage: in original: %([\d*\.]+)') {
                $lastMatchPercent = [double]$matches[1]
            }
        }
         $result="-"
        if($lastMatchPercent -gt 70){
            $result="OK"
        }
        $totalsecs=$total/1000
        #CDM testing
        $cdm_after=cdm -logname "$($index)_$($type)_$($unitsizstring)_CDMTest_after"
        $freeafter = "{0:N2}" -f $((Get-PSDrive -Name $driverletter).Free)
        $vol = Get-Volume -DriveLetter $driverletter
        $actualFS       = $vol.FileSystem
        $actualCluster  = $vol.AllocationUnitSize
        $actualalll  = "{0} bytes" -f ($actualCluster)
        if ($actualCluster -ge 15KB) {
        $actualalll = "{0} kilibytes" -f ($actualCluster/ 1KB)
        }
        $sizeGB = [math]::Round($vol.Size / 1GB,2)
        $formattime = "$($totalsecs)s"
        $driverpath="$($driverletter):"
        $logtime=get-date -format "yy/MM/dd HH:mm:ss"
        $formatresult=[PSCustomObject]@{
            Drive              = $driverpath
            FileSystem         = $actualFS
            AllocationUnitSize = $actualalll
            formattime         = $formattime
            VolumeSize_GB      = $sizeGB
            diskfree_Before    = $freebefore
            diskfree_After     = $freeafter
            CDM_Read_Before    = $cdm_before[0]
            CDM_Write_Before   = $cdm_before[1]
            CDM_Read_After     = $cdm_after[0]
            CDM_Write_After    = $cdm_after[1]
            Criteria           = "TBD"
            Result             = $result
            Index              = $index
            logtime            = $logtime
            }
    $formatresult|export-csv -Path $formatcsvlog -Encoding UTF8 -NoTypeInformation -Append
    }
}
}
function win11format([string]$index,[switch]$nonquick,[switch]$withfile,[switch]$fillfile){
installjava
downloadsikuli
$foldername="WIN11"
$clickname="format"
$fillfiletake="-"
$picfolder=(join-path $picfolder $index).tostring()
$matrix=import-csv $settingpath
$types=$matrix.FileSystem|Get-Unique
$javalog="$modulepath\clicktool\SikuliLog_*.log"
$skipcomb=@()
if($withfile){
    $matrix|Where-Object{$_."skip_withfile" -ne ""}|ForEach-Object{
    $skipcomb+= "$($_."FileSystem")$($_."Support"))"
    }
   }
   else{
     $matrix|Where-Object{$_."skip_nofile" -ne ""}|ForEach-Object{
     $skipcomb+= "$($_."FileSystem")$($_."Support"))"
    }
   }
 if($withfile){
  #region create 5GB file
    outlog "format with file"
    $formatfilesize=5GB
    if($formatfilesize -ge 1GB){
        $filename="$($formatfilesize/1GB)GB"
    }
    elseif($formatfilesize -ge 1MB){
        $filename="$($formatfilesize/1MB)MB"
    }
    $filefull=(join-path $logfolder "$($filename).bin").ToString()
    if(!(test-path $filefull)){
    $formatfilebytes=[int64]$formatfilesize.ToString()
    fsutil file createNew $filefull $formatfilebytes
    outlog "$filefull create done"
    }
    #endregion
}
foreach($type in $types){
    $downselect1=$types.indexof($type)+1
    $unitsizes=($matrix|Where-Object{$_.FileSystem -eq $type}).Support
    foreach($unitsiz in $unitsizes){
        $settingcomb="$($type)$($unitsiz)"
        if($settingcomb -in $skipcomb){
            continue
        }
        $downselect2=$unitsizes.indexof($unitsiz)+1
        if($fillfile -and $downselect2 -gt 1){
            continue
        }
        $unitsizstring="{0} bytes" -f $unitsiz
        if ([int64]$unitsiz -ge 1KB) {
        $unitsizstring = "{0} KB" -f ($unitsiz/ 1KB)
        }
        $picnamestart="$($type)_$($unitsizstring)_Format_start"
        $picnamecomplete="$($type)_$($unitsizstring)_Format_complete"
        #region 5G copy
        if($withfile){
        if(!(test-path $filefull)){
        fsutil file createnew $filefull $formatfilebytes|Out-Null
            }
        $dest = "$driverletter`:\"
        $sw = [Diagnostics.Stopwatch]::StartNew()
        Copy-Item -Path $filefull -Destination $dest -Force -ErrorAction SilentlyContinue
        $sw.Stop()
        $copytakes="$([math]::Round($sw.Elapsed.TotalSeconds,2)) sec"
        $minutes = [int]$sw.Elapsed.TotalMinutes
        $seconds = [int] $sw.Elapsed.Seconds
        $totalsecs = $runningtime.TotalSeconds
        $copytakes = "{0}min {1}s" -f $minutes, $seconds
        }
        #endregion
        #region fillfile in disk 
        if($fillfile){
           . $rootpath\filldisk.exe
         <#   
        $filldisk=FileCreate -FillDisk
        #>
        diskexploropen -openpath "shell:MyComputerFolder" -disk
        screenshot -picpath $picfolder -picname "Filldisk_BeforeFormat"
        $ws.SendKeys("%{F4}") #close file explore
        }
        #endregion
        $freebefore = "{0:N2}" -f $((Get-PSDrive -Name $driverletter).Free)
        #cdm test before formating
        $cdm_before=cdm -logname "$($index)_$($type)_$($unitsizstring)_CDMTestbefore"
        start-sleep -s 5
        openformat
        click -foldername $foldername -imagef $clickname -pyfile "click.py" -passkey "CLICK on"
        #save format time
        $ws.SendKeys("{TAB}")
        Start-Sleep -Milliseconds 500
        #select fiile system
        #reset to top
        for($x=1;$x -le 5;$x++){
            $ws.SendKeys("{UP}")
            Start-Sleep -Milliseconds 200
        }
        #select
        for($x=1;$x -lt $downselect1;$x++){
            $ws.SendKeys("{Down}")
            Start-Sleep -Milliseconds 500
        }
        $ws.SendKeys("{TAB}")
        Start-Sleep -Milliseconds 500
        #reset to top
        for($x=1;$x -le 20;$x++){
            $ws.SendKeys("{UP}")
            Start-Sleep -Milliseconds 200
        }
        #select alllocated unit size
        for($x=1;$x -lt $downselect2;$x++){
            $ws.SendKeys("{Down}")
            Start-Sleep -Milliseconds 500
        }
        if([int64]$unitsiz -lt 8000){
        $ws.SendKeys("{TAB}")
        Start-Sleep -Milliseconds 500
        }
        $ws.SendKeys("{TAB}")
        Start-Sleep -Milliseconds 500
        if($nonquick){
        $ws.SendKeys(" ")
        Start-Sleep -Milliseconds 500
        }
        $ws.SendKeys("{TAB}")
        Start-Sleep -s 1
        screenshot -picpath $picfolder -picname $picnamestart
        outlog "$($index)_$($type)_$($unitsizstring)_FormatStart"
        $ws.SendKeys("{Enter}")
        Start-Sleep -s 5
        [Clicker]::LeftClickAtPoint($screenwidth/2, $screenheight/2)
        Start-Sleep -s 1
        $ws.SendKeys("{TAB}")
        Start-Sleep -s 1
        $ws.SendKeys("{TAB}")
        Start-Sleep -s 1
        $ws.SendKeys("{Enter}")
        if($sw){
        $sw.reset()
        }
        $sw = [Diagnostics.Stopwatch]::StartNew()
        $dirverdisk="$($driverletter):\"
        $diskback=$false
         while(!$diskback){
          $diskback= Get-item $dirverdisk -ErrorAction Ignore
          start-sleep -s 1
        }
        $sw.stop()
        outlog "$($index)_$($type)_$($unitsizstring)_FormatComplete"
        $totalsecs = [math]::Round($sw.Elapsed.TotalSeconds, 2)
        $formattime = "{0}min {1}s" -f $minutes, $seconds
        $minutes = [int]($runningtime.TotalMinutes)
        [int]$seconds= 0 
        $minutes = [math]::DivRem([int]$runningtime.TotalSeconds, 60, [ref]$seconds)
        $totalsecs =[math]::round($runningtime.TotalSeconds,2 )
        $runtimeText = "{0}min {1}s" -f $minutes, $seconds
        $formattime  = "$totalsecs s ($runtimeText)"
        start-sleep -s 10
        screenshot -picpath $picfolder -picname $picnamecomplete
        diskexploropen -openpath "shell:MyComputerFolder" -disk
        screenshot -picpath $picfolder -picname "Filldisk_BeforeFormat"
        $ws.SendKeys("%{F4}") #close file explore
        #CDM testing
        $cdm_after=cdm -logname "$($index)_$($type)_$($unitsizstring)_CDMTest_after"
        start-sleep -s 5
        $freeafter = "{0:N2}" -f $((Get-PSDrive -Name $driverletter).Free)
        $vol = Get-Volume -DriveLetter $driverletter
        $actualFS       = $vol.FileSystem
        $actualCluster  = $vol.AllocationUnitSize
        $actualalll  = "{0} bytes" -f ($actualCluster)
        if ($actualCluster -ge 15KB) {
        $actualalll = "{0} kilibytes" -f ($actualCluster/ 1KB)
        }
        $sizeGB = [math]::Round($vol.Size / 1GB,2)
        $formattime = "$($totalsecs)s"
        $driverpath="$($driverletter):"
        $logtime=get-date -format "yy/MM/dd HH:mm:ss"
        $formatresult=[PSCustomObject]@{
            Drive              = $driverpath
            FileSystem         = $actualFS
            AllocationUnitSize = $actualalll
            formattime         = $formattime
            VolumeSize_GB      = $sizeGB
            diskfree_Before    = $freebefore
            diskfree_After     = $freeafter
            CDM_Read_Before    = $cdm_before[0]
            CDM_Write_Before   = $cdm_before[1]
            CDM_Read_After     = $cdm_after[0]
            CDM_Write_After    = $cdm_after[1]
            Criteria           = "TBD"
            Result             = $result
            Index              = $index
            logtime            = $logtime
            }
    $formatresult|export-csv -Path $formatcsvlog -Encoding UTF8 -NoTypeInformation -Append
    get-process -name "systemsettings"|stop-process
    }
}
}

function openformat{
$coors=get-content $modulepath/coordinate_check_tool/click.txt
$clickx=($coors.split(","))[0]
$clicky=($coors.split(","))[1]
 Start-Process ms-settings:disksandvolumes
 start-sleep -s 20
[KeySends.KeySend]::KeyDown([System.Windows.Forms.Keys]::Menu)
 start-sleep -Milliseconds 100
[KeySends.KeySend]::KeyDown([System.Windows.Forms.Keys]::Space)
 start-sleep -Milliseconds 200
[KeySends.KeySend]::KeyUp([System.Windows.Forms.Keys]::Menu)
 start-sleep -Milliseconds 100
[KeySends.KeySend]::KeyUp([System.Windows.Forms.Keys]::Space)
 start-sleep -Milliseconds 200
  $ws.SendKeys("x")
  start-sleep -s 1
  1..5 | ForEach-Object {
    $ws.SendKeys("{PGDN}")
    Start-Sleep -Milliseconds 200
}
[Mouse]::mouse_event(0x0800, 0, 0, -120, 0)
  start-sleep -s 1
 [Clicker]::LeftClickAtPoint($clickx, $clicky)
  start-sleep -s 2
  $ws.SendKeys("{DOWN 2}")
}
