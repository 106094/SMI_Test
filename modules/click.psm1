$psroot="$modulepath\click"

function installjava([int32]$ver,[switch]$testing){

    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (!$isAdmin) {
        Start-Process powershell.exe -Verb RunAs -ArgumentList "-File `"$PSCommandPath`""
        Exit
    }

$jdk_folder="$psroot\java\"
if (!($env:JAVA_HOME -eq $jdk_folder)){
    Write-Output "need install java"
    $ver=23
    $downloadlink=((Invoke-WebRequest https://jdk.java.net/$($ver)/).links|Where-Object {$_.href -match "windows" -and $_.innerHTML -eq "zip"}).href
    $jdk_zip_file="$psroot\java.zip"
    if(!$testing){
    Invoke-WebRequest $downloadlink -OutFile $jdk_zip_file
    Expand-Archive -Path $jdk_zip_file -DestinationPath "$psroot\java"
    Remove-Item -Path $jdk_zip_file
    }
    $javabin=(get-childitem $psroot\java\ -Directory -r |Where-Object{$_.name -match "bin"}).FullName
    # Set Environment Variables
    $path = [System.Environment]::GetEnvironmentVariable('Path', 'Machine')
    [System.Environment]::SetEnvironmentVariable('Path', $path + ';' + $javabin, 'Machine')

    [Environment]::SetEnvironmentVariable('JAVA_HOME', $jdk_folder, 'Machine')
    [Environment]::SetEnvironmentVariable('JDK_HOME', $jdk_folder, 'Machine')
    [Environment]::SetEnvironmentVariable('JRE_HOME', $jdk_folder, 'Machine')
    # Reload system environment variables
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", [System.EnvironmentVariableTarget]::Machine) + ";" + 
    [System.Environment]::GetEnvironmentVariable("Path", [System.EnvironmentVariableTarget]::User)

    $checkJavaInstall = & java -version 2>&1
    Write-Output $checkJavaInstall
}
else{
    java -version
    Write-Output "already installed Java"
}
}
function downloadsikuli{
    $sikulipath="$psroot\sikulixide-2.0.5.jar"
    if(!(test-path  $sikulipath)){
        Invoke-WebRequest  "https://launchpad.net/sikuli/sikulix/2.0.5/+download/sikulixide-2.0.5.jar" -OutFile $sikulipath
        if(test-path  $sikulipath){
            Write-Output "sikuli downloaded ok"
           }
        }

       else{
        Write-Output "sikuli already downloaded"
       }
}

function click([string]$imagef,[string]$foldername){
    $success=$false
    $pngs=Get-ChildItem ($psroot+"\click.sikuli\$($foldername)\$($imagef)\*.png")
    $logspath="$psroot\SikuliLogs.txt"
    $clickpng="$psroot\click.sikuli\click.png"
    if(!(test-path  $logspath)){
        New-Item -Path $logspath -ItemType File|out-null
    }
    foreach($png in $pngs){
        $pngpath=$png.FullName
        $pngname=$png.Name
        Copy-Item -path $pngpath -Destination $clickpng -force
        java -jar "$psroot\sikulixide-2.0.5.jar" -r $psroot\click.sikuli\ -v -f $psroot\SikuliLog.txt
        $resultclick=get-content $psroot\SikuliLog.txt
        if( $resultclick -like "*CLICK on*"){
            $success=$true
            break  
        }           
       remove-item $clickpng -Force            
    }
    if($success){
        add-content $logspath -Value "$(get-date -Format "yy/MM/dd HH:mm:ss"): click on $($foldername)/$($imagef)/$($pngname) ok"
         write-host "$(get-date -Format "yy/MM/dd HH:mm:ss"): click on $($foldername)/$($imagef)/$($pngname) ok" -ForegroundColor Green
    }else{
        add-content $logspath -Value "$(get-date -Format "yy/MM/dd HH:mm:ss"): click on $($foldername)/$($imagef) fail"
        write-host "$(get-date -Format "yy/MM/dd HH:mm:ss"): click on $($foldername)/$($imagef) fail" -ForegroundColor red
    }

}

function capture ([string]$foldername){
    $capturef="$psroot\capture.sikuli\_capture.png"
    if(test-path  $capturef -ea SilentlyContinue){
    try{
        remove-item $capturef -Force
    }
    catch{
      write-host "error to delete capture file. Need to check" -ForegroundColor lightred
      exit
    }
    }
    java -jar "$psroot\sikulixide-2.0.5.jar" -r $psroot\capture.sikuli\ -v -f $psroot\SikuliLog.txt
    #popup the name of the capture folder
    $pngfolder="$psroot\click.sikuli\png\$($foldername)\"
    if (!(test-path $pngfolder)){
        New-Item -Path $pngfolder -ItemType Directory|out-null
    }
    $filepng=(get-date -Format "yyMMddHHmmss"|Out-String).trim()+".png"
    $filefull=join-path $pngfolder $filepng
    copy-item -path "$psroot\capture.sikuli\_capture.png" -Destination $filefull
    remove-item $capturef -Force
}

$checkjava= java --version

if(!$checkjava){
installjava 23
downloadsikuli
}
