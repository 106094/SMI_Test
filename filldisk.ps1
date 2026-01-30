function get_driverletter {
    # Using Get-CimInstance for better performance in compiled EXEs
    $removable = Get-CimInstance Win32_Volume -Filter "DriveType=2" | Select-Object -ExpandProperty DriveLetter
    
    if (!$removable) {
        # Fallback to Fixed drives that aren't C:
        $removable = Get-CimInstance Win32_Volume -Filter "DriveType=3" | 
                     Where-Object { $_.DriveLetter -and $_.DriveLetter -notmatch "C:" } | 
                     Select-Object -ExpandProperty DriveLetter
    }

    if (!$removable) {
        [void][System.Windows.Forms.MessageBox]::Show("No USB disk found.", "System Alert", "OK", "Warning")
        return $null
    }

    if ($removable.Count -gt 1) {
        [void][System.Windows.Forms.MessageBox]::Show("Please leave only one USB drive connected!", "System Alert", "OK", "Warning")
        return $null
    }

    return $removable
}


$diskpath = get_driverletter
if ($null -eq $diskpath) { exit }

$driverletter = $diskpath.Replace(":", "")
$Filepath = Join-Path $diskpath "test.bin"

 format "$($driverletter):" /FS:NTFS /V:Test /Q /X /Y |out-null

# Get free space and ensure it stays as a 64-bit integer
$freeSpace = (Get-PSDrive -Name $driverletter).Free
$targetSize = [int64]($freeSpace -1.1GB)

# SAFETY CHECK: If the drive has less than 1.1GB, $targetSize will be <= 0
if ($targetSize -le 0) {
    Write-Error "Not enough space to leave 1.1GB free. (Current Free: $([Math]::Round($freeSpace/1MB, 2)) MB)"
    exit
}

try {
    # Open with 'ReadWrite' sharing to prevent some OS-level locking hangs
    $fs = [System.IO.File]::Open($Filepath, 'Create', 'Write', 'ReadWrite')
    
    Write-Host "Allocating space: $([Math]::Round($targetSize/1GB, 2)) GB..."
    $fs.SetLength($targetSize)
    
    # Flush and Release
    $fs.Flush($true)
    $fs.Dispose()
    Write-Host "File handle released successfully."
}
catch {
    Write-Error "File Operation Failed: $($_.Exception.Message)"
    if ($fs) { $fs.Dispose() }
}