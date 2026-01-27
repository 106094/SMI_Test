
$psroot="$modulepath\clicktool"

function get_driverletter{
    $driverletter=(Get-WmiObject Win32_Volume -Filter ("DriveType={0}" -f [int][System.IO.DriveType]::Removable)).DriveLetter 
    if(!$driverletter){
      $readhost=Read-Host "No USB disk found, please insert one USB fresh drive to test"
    }
    if($driverletter.count -gt 1){
      $readhost=Read-Host "No USB fresh drive is found, please insert one USB fresh drive to test"
      $ws.Popup("Please left Only One USB fresh drive for test!", 0, "System Alert", 48 + 0)
    }
    return $driverletter
}
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


$source = @"
using System;
using System.Threading.Tasks;
using System.Runtime.InteropServices;
using System.Windows.Forms;
namespace KeySends
{
    public class KeySend
    {
        [DllImport("user32.dll")]
        public static extern void keybd_event(byte bVk, byte bScan, int dwFlags, int dwExtraInfo);
        private const int KEYEVENTF_EXTENDEDKEY = 1;
        private const int KEYEVENTF_KEYUP = 2;
        public static void KeyDown(Keys vKey)
        {
            keybd_event((byte)vKey, 0, KEYEVENTF_EXTENDEDKEY, 0);
        }
        public static void KeyUp(Keys vKey)
        {
            keybd_event((byte)vKey, 0, KEYEVENTF_EXTENDEDKEY | KEYEVENTF_KEYUP, 0);
        }
    }
}
"@
Add-Type -TypeDefinition $source -ReferencedAssemblies "System.Windows.Forms"

 function Set-WindowState {
	<#
	.LINK
	https://gist.github.com/Nora-Ballard/11240204
	#>

	[CmdletBinding(DefaultParameterSetName = 'InputObject')]
	param(
		[Parameter(Position = 0, Mandatory = $true, ValueFromPipeline = $true)]
		[Object[]] $InputObject,

		[Parameter(Position = 1)]
		[ValidateSet('FORCEMINIMIZE', 'HIDE', 'MAXIMIZE', 'MINIMIZE', 'RESTORE',
					 'SHOW', 'SHOWDEFAULT', 'SHOWMAXIMIZED', 'SHOWMINIMIZED',
					 'SHOWMINNOACTIVE', 'SHOWNA', 'SHOWNOACTIVATE', 'SHOWNORMAL')]
		[string] $State = 'SHOW'
	)

	Begin {
		$WindowStates = @{
			'FORCEMINIMIZE'		= 11
			'HIDE'				= 0
			'MAXIMIZE'			= 3
			'MINIMIZE'			= 6
			'RESTORE'			= 9
			'SHOW'				= 5
			'SHOWDEFAULT'		= 10
			'SHOWMAXIMIZED'		= 3
			'SHOWMINIMIZED'		= 2
			'SHOWMINNOACTIVE'	= 7
			'SHOWNA'			= 8
			'SHOWNOACTIVATE'	= 4
			'SHOWNORMAL'		= 1
		}

		$Win32ShowWindowAsync = Add-Type -MemberDefinition @'
[DllImport("user32.dll")]
public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);
'@ -Name "Win32ShowWindowAsync" -Namespace Win32Functions -PassThru

		if (!$global:MainWindowHandles) {
			$global:MainWindowHandles = @{ }
		}
	}

	Process {
		foreach ($process in $InputObject) {
			if ($process.MainWindowHandle -eq 0) {
				if ($global:MainWindowHandles.ContainsKey($process.Id)) {
					$handle = $global:MainWindowHandles[$process.Id]
				} else {
					Write-Error "Main Window handle is '0'"
					continue
				}
			} else {
				$handle = $process.MainWindowHandle
				$global:MainWindowHandles[$process.Id] = $handle
			}

			$Win32ShowWindowAsync::ShowWindowAsync($handle, $WindowStates[$State]) | Out-Null
			Write-Verbose ("Set Window State '{1} on '{0}'" -f $MainWindowHandle, $State)
		}
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


$cSource = @'
using System;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Windows.Forms;
public class Clicker
{
//https://msdn.microsoft.com/en-us/library/windows/desktop/ms646270(v=vs.85).aspx
[StructLayout(LayoutKind.Sequential)]
struct INPUT
{ 
    public int        type; // 0 = INPUT_MOUSE,
                            // 1 = INPUT_KEYBOARD
                            // 2 = INPUT_HARDWARE
    public MOUSEINPUT mi;
}

//https://msdn.microsoft.com/en-us/library/windows/desktop/ms646273(v=vs.85).aspx
[StructLayout(LayoutKind.Sequential)]
struct MOUSEINPUT
{
    public int    dx ;
    public int    dy ;
    public int    mouseData ;
    public int    dwFlags;
    public int    time;
    public IntPtr dwExtraInfo;
}

//This covers most use cases although complex mice may have additional buttons
//There are additional constants you can use for those cases, see the msdn page
const int MOUSEEVENTF_MOVED      = 0x0001 ;
const int MOUSEEVENTF_LEFTDOWN   = 0x0002 ;
const int MOUSEEVENTF_LEFTUP     = 0x0004 ;
const int MOUSEEVENTF_RIGHTDOWN  = 0x0008 ;
const int MOUSEEVENTF_RIGHTUP    = 0x0010 ;
const int MOUSEEVENTF_MIDDLEDOWN = 0x0020 ;
const int MOUSEEVENTF_MIDDLEUP   = 0x0040 ;
const int MOUSEEVENTF_WHEEL      = 0x0080 ;
const int MOUSEEVENTF_XDOWN      = 0x0100 ;
const int MOUSEEVENTF_XUP        = 0x0200 ;
const int MOUSEEVENTF_ABSOLUTE   = 0x8000 ;

const int screen_length = 0x10000 ;

//https://msdn.microsoft.com/en-us/library/windows/desktop/ms646310(v=vs.85).aspx
[System.Runtime.InteropServices.DllImport("user32.dll")]
extern static uint SendInput(uint nInputs, INPUT[] pInputs, int cbSize);

public static void LeftClickAtPoint(int x, int y)
{
    //Move the mouse
    INPUT[] input = new INPUT[3];
    input[0].mi.dx = x*(65535/System.Windows.Forms.Screen.PrimaryScreen.Bounds.Width);
    input[0].mi.dy = y*(65535/System.Windows.Forms.Screen.PrimaryScreen.Bounds.Height);
    input[0].mi.dwFlags = MOUSEEVENTF_MOVED | MOUSEEVENTF_ABSOLUTE;
    //Left mouse button down
    input[1].mi.dwFlags = MOUSEEVENTF_LEFTDOWN;
    //Left mouse button up
    input[2].mi.dwFlags = MOUSEEVENTF_LEFTUP;
    SendInput(3, input, Marshal.SizeOf(input[0]));
}
public static void rightClickAtPoint(int x, int y)
{
    //Move the mouse
    INPUT[] input = new INPUT[3];
    input[0].mi.dx = x*(65535/System.Windows.Forms.Screen.PrimaryScreen.Bounds.Width);
    input[0].mi.dy = y*(65535/System.Windows.Forms.Screen.PrimaryScreen.Bounds.Height);
    input[0].mi.dwFlags = MOUSEEVENTF_MOVED | MOUSEEVENTF_ABSOLUTE;
    //Left mouse button down
    input[1].mi.dwFlags = MOUSEEVENTF_RIGHTDOWN;
    //Left mouse button up
    input[2].mi.dwFlags = MOUSEEVENTF_RIGHTUP;
    SendInput(3, input, Marshal.SizeOf(input[0]));
}
}
'@
Add-Type -TypeDefinition $cSource -ReferencedAssemblies System.Windows.Forms,System.Drawing

function Set-WindowState {
	<#
	.LINK
	https://gist.github.com/Nora-Ballard/11240204
	#>

	[CmdletBinding(DefaultParameterSetName = 'InputObject')]
	param(
		[Parameter(Position = 0, Mandatory = $true, ValueFromPipeline = $true)]
		[Object[]] $InputObject,

		[Parameter(Position = 1)]
		[ValidateSet('FORCEMINIMIZE', 'HIDE', 'MAXIMIZE', 'MINIMIZE', 'RESTORE',
					 'SHOW', 'SHOWDEFAULT', 'SHOWMAXIMIZED', 'SHOWMINIMIZED',
					 'SHOWMINNOACTIVE', 'SHOWNA', 'SHOWNOACTIVATE', 'SHOWNORMAL')]
		[string] $State = 'SHOW'
	)

	Begin {
		$WindowStates = @{
			'FORCEMINIMIZE'		= 11
			'HIDE'				= 0
			'MAXIMIZE'			= 3
			'MINIMIZE'			= 6
			'RESTORE'			= 9
			'SHOW'				= 5
			'SHOWDEFAULT'		= 10
			'SHOWMAXIMIZED'		= 3
			'SHOWMINIMIZED'		= 2
			'SHOWMINNOACTIVE'	= 7
			'SHOWNA'			= 8
			'SHOWNOACTIVATE'	= 4
			'SHOWNORMAL'		= 1
		}

		$Win32ShowWindowAsync = Add-Type -MemberDefinition @'
[DllImport("user32.dll")]
public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);
'@ -Name "Win32ShowWindowAsync" -Namespace Win32Functions -PassThru

		if (!$global:MainWindowHandles) {
			$global:MainWindowHandles = @{ }
		}
	}

	Process {
		foreach ($process in $InputObject) {
			if ($process.MainWindowHandle -eq 0) {
				if ($global:MainWindowHandles.ContainsKey($process.Id)) {
					$handle = $global:MainWindowHandles[$process.Id]
				} else {
					Write-Error "Main Window handle is '0'"
					continue
				}
			} else {
				$handle = $process.MainWindowHandle
				$global:MainWindowHandles[$process.Id] = $handle
			}

			$Win32ShowWindowAsync::ShowWindowAsync($handle, $WindowStates[$State]) | Out-Null
			Write-Verbose ("Set Window State '{1} on '{0}'" -f $MainWindowHandle, $State)
		}
	}
}
#[Clicker]::LeftClickAtPoint($x1, $y1)

### minimized cmd window ###
function minimized {
    param (
    $hideappnames
    )
    $hideappnames|ForEach-Object{
    $processname=$_
    $lastid= (Get-Process -name $processname -ea SilentlyContinue |Sort-Object StartTime  |Select-Object -last 1)
    if($lastid -and $lastid.mainwindowhandle -ne 0){
    Get-Process -id $lastid.id  | Set-WindowState -State MINIMIZE
    Start-Sleep -s 1
    }
    }
    
}
function screenshot([string]$picpath,[string]$picname){
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Native {
  [DllImport("user32.dll")] public static extern IntPtr GetDC(IntPtr hwnd);
  [DllImport("user32.dll")] public static extern int ReleaseDC(IntPtr hwnd, IntPtr hdc);
  [DllImport("gdi32.dll")] public static extern int GetDeviceCaps(IntPtr hdc, int nIndex);
}
"@
 $hdc = [Native]::GetDC([IntPtr]::Zero)
  try {
    # 118/117 = DESKTOPHORZRES / DESKTOPVERTRES (real pixel resolution)
    $pxW = [Native]::GetDeviceCaps($hdc, 118) # width
    $pxH = [Native]::GetDeviceCaps($hdc, 117) # height
  }
  finally {
    [void][Native]::ReleaseDC([IntPtr]::Zero, $hdc)
  }
 $bmp = New-Object System.Drawing.Bitmap($pxW, $pxH)
 $g   = [System.Drawing.Graphics]::FromImage($bmp)
 try {
    $g.CopyFromScreen(0, 0, 0, 0, $bmp.Size)
    $datesuffix = Get-Date -Format "-yyMMdd_HHmmss"
    $safeName = ($picname -replace '[\\/:*?"<>|]', '_')
    $full = Join-Path $picpath ($safeName + $datesuffix + ".jpg")
    $picsavepath=split-path $full
        if(!(test-path $picsavepath)){
        new-item -ItemType Directory -Path $picsavepath|Out-Null
    }
    $bmp.Save($full, [System.Drawing.Imaging.ImageFormat]::Jpeg)
  }
  finally {
    $g.Dispose()
    $bmp.Dispose()
  }
  
}

function Get-AppWindowRect {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProcessName,

        [ValidateSet('First','Largest','Newest')]
        [string]$Pick = 'First',
        [int]$ClickShiftX = 10,
        [int]$ClickShiftY = 10,
        [switch]$Activate,        
        [switch]$shiftpercentage
    )

    # ---- Add Win32 type only once ----
    if (-not ("Win32User32" -as [type])) {
        Add-Type -Language CSharp -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public static class Win32User32 {
    [DllImport("user32.dll")]
    public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);

    [DllImport("user32.dll")]
    public static extern bool IsIconic(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }
}
"@
    }

    $procs = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue |
             Where-Object { $_.MainWindowHandle -ne 0 }

    if (-not $procs) { return $null }

    $p = switch ($Pick) {
        'Largest' { $procs | Sort-Object { $_.MainWindowRect.Width * $_.MainWindowRect.Height } -Descending | Select-Object -First 1 }
        'Newest'  { $procs | Sort-Object StartTime -Descending | Select-Object -First 1 }
        default   { $procs | Select-Object -First 1 }
    }

    $hWnd = [IntPtr]$p.MainWindowHandle

    if ($Activate) {
        if ([Win32User32]::IsIconic($hWnd)) {
            [Win32User32]::ShowWindow($hWnd, 9) | Out-Null  # SW_RESTORE
        }
        [Win32User32]::SetForegroundWindow($hWnd) | Out-Null
        Start-Sleep -Milliseconds 150
    }

    $rect = New-Object Win32User32+RECT
    if (-not [Win32User32]::GetWindowRect($hWnd, [ref]$rect)) {
        throw "GetWindowRect failed for $ProcessName"
    }
    $width = ($rect.Right - $rect.Left)
    $height = ($rect.Bottom - $rect.Top)
    if($shiftpercentage){
        $ClickShiftX=$width/100*$ClickShiftX
        $ClickShiftY=$height/100*$ClickShiftY
    }
    

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class PInvoke {
    [DllImport("user32.dll")] public static extern IntPtr GetDC(IntPtr hwnd);
    [DllImport("gdi32.dll")] public static extern int GetDeviceCaps(IntPtr hdc, int nIndex);
}
"@
    $hdc = [PInvoke]::GetDC([IntPtr]::Zero)
    $curwidth = [PInvoke]::GetDeviceCaps($hdc, 118) # width
    $curheight = [PInvoke]::GetDeviceCaps($hdc, 117) # height

    $script:screen = [System.Windows.Forms.Screen]::PrimaryScreen
    $bounds = $screen.Bounds

    $currentDPI = (Get-ItemProperty -Path "HKCU:\Control Panel\Desktop\WindowMetrics" -Name AppliedDPI).AppliedDPI

    $dpisets=@(96,120,144,168)
    $sclsets=@(100,125,150,175)

    $index = $dpisets.IndexOf($currentDPI)
    $calcu = $sclsets[$index] /100

    [PSCustomObject]@{
        ProcessName = $p.ProcessName
        Id          = $p.Id
        Title       = $p.MainWindowTitle
        Handle      = $hWnd
        Left        = $rect.Left
        Top         = $rect.Top
        Right       = $rect.Right
        Bottom      = $rect.Bottom
        Width       = $width
        Height      = $height
        ClickX      = ($rect.Left + $ClickShiftX)/$calcu
        ClickY      = ($rect.Top  + $ClickShiftY)/$calcu
    }
}

function Get-PopupWindowText {
    param(
        [string]$TitleRegex = 'Format|Warning|Disk'
    )

    $root = [System.Windows.Automation.AutomationElement]::RootElement

    $condition = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
        [System.Windows.Automation.ControlType]::Window
    )

    $windows = $root.FindAll(
        [System.Windows.Automation.TreeScope]::Children,
        $condition
    )

    foreach ($win in $windows) {
        $name = $win.Current.Name
        if ($name -match $TitleRegex) {
            $texts = $win.FindAll(
                [System.Windows.Automation.TreeScope]::Descendants,
                (New-Object System.Windows.Automation.PropertyCondition(
                    [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
                    [System.Windows.Automation.ControlType]::Text
                ))
            )

            return  [PSCustomObject]@{
                Title = $name
                Text  = ($texts | ForEach-Object { $_.Current.Name }) -join "`n"
            }
        }
    }
}
function csvlogname([string]$filename){
$datetime=get-date -format "_yyMMdd_HHmmss"
$filenname="$($filename)$($datetime).csv"
$outfilenname=(join-path $logfolder $filenname).ToString()
return $outfilenname
}

<#
$script:screen = [System.Windows.Forms.Screen]::PrimaryScreen 
$bounds = $screen.Bounds 
$currentDPI = (Get-ItemProperty -Path "HKCU:\Control Panel\Desktop\WindowMetrics" -Name AppliedDPI).AppliedDPI 
$dpisets=@(96,120,144,168) 
$sclsets=@(100,125,150,175) 
$index = $dpisets.IndexOf($currentDPI) 
$calcu = $sclsets[$index] /100 
$bounds.Width = $curwidth * $calcu 
$bounds.Height = $curheight * $calcu
#>