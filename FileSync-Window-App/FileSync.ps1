# ============================================================
# File Sync Daemon - Continuous Background Sync
# Uses FileSystemWatcher for real-time file monitoring
# Author: Abhishek Singh
# ============================================================

param(
    [Parameter(Mandatory=$true)]
    [string]$SourceFolder,
    
    [Parameter(Mandatory=$true)]
    [string]$TargetFolder,
    
    [Parameter(Mandatory=$false)]
    [string]$ShowNotifications = "False",
    
    [Parameter(Mandatory=$false)]
    [string]$LogFilePath = "",
    
    [Parameter(Mandatory=$false)]
    [string]$PidFilePath = "",
    
    [Parameter(Mandatory=$false)]
    [string]$StopFilePath = ""
)

# Convert string parameter to boolean
$script:ShowNotifications = ($ShowNotifications -eq "True" -or $ShowNotifications -eq "1")

# ============================================================
# EARLY ERROR CAPTURE
# ============================================================
$ErrorActionPreference = "Continue"

try {
    # Setup log path
    if ([string]::IsNullOrEmpty($LogFilePath)) {
        $logFolder = Join-Path -Path $env:USERPROFILE -ChildPath "FileSyncLogs"
        $LogFilePath = Join-Path -Path $logFolder -ChildPath "FileSyncDaemon.log"
    }
    
    $logFolder = Split-Path -Path $LogFilePath -Parent
    
    if (-not (Test-Path -Path $logFolder)) {
        New-Item -Path $logFolder -ItemType Directory -Force | Out-Null
    }
    
    # Write startup marker immediately
    $startupMarker = "[" + (Get-Date -Format "yyyy-MM-dd HH:mm:ss") + "] [STARTUP] Daemon script invoked. PID: $PID"
    Add-Content -Path $LogFilePath -Value $startupMarker -ErrorAction Stop
    Add-Content -Path $LogFilePath -Value "[STARTUP] PowerShell Version: $($PSVersionTable.PSVersion)" -ErrorAction Stop
    
    # Write PID file
    if (-not [string]::IsNullOrEmpty($PidFilePath)) {
        $PID | Out-File -FilePath $PidFilePath -Force -Encoding ASCII -ErrorAction Stop
    }
}
catch {
    $fallbackLog = Join-Path -Path $env:TEMP -ChildPath "FileSync_CRITICAL_ERROR.log"
    $errMsg = "[" + (Get-Date -Format "yyyy-MM-dd HH:mm:ss") + "] CRITICAL: $_"
    try {
        Add-Content -Path $fallbackLog -Value $errMsg
    } catch {}
    exit 99
}

# ============================================================
# Helper Functions
# ============================================================
function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[" + $timestamp + "] [" + $Level + "] " + $Message
    
    try {
        Add-Content -Path $LogFilePath -Value $logEntry -ErrorAction Stop
    }
    catch {
        # Silent fail
    }
}

function Show-Notification {
    param(
        [string]$Title,
        [string]$Message
    )
    
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
        Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue
        
        $notify = New-Object System.Windows.Forms.NotifyIcon
        $notify.Icon = [System.Drawing.SystemIcons]::Information
        $notify.BalloonTipTitle = $Title
        $notify.BalloonTipText = $Message
        $notify.BalloonTipIcon = "Info"
        $notify.Visible = $true
        $notify.ShowBalloonTip(3000)
        
        Start-Sleep -Milliseconds 3500
        $notify.Dispose()
    }
    catch {
        # Silent fail
    }
}

function Test-FileDifferent {
    param(
        [string]$SourceFile,
        [string]$DestFile
    )
    
    if (-not (Test-Path -Path $DestFile)) { return $true }
    
    try {
        $srcInfo = Get-Item -Path $SourceFile -ErrorAction Stop
        $dstInfo = Get-Item -Path $DestFile -ErrorAction Stop
        
        if ($srcInfo.Length -ne $dstInfo.Length) { return $true }
        if ($srcInfo.LastWriteTime -gt $dstInfo.LastWriteTime) { return $true }
    }
    catch {
        return $true
    }
    
    return $false
}

function Sync-SingleFile {
    param(
        [string]$SourceFile,
        [string]$Source,
        [string]$Destination
    )
    
    try {
        # Wait for file to be released by writing app
        Start-Sleep -Milliseconds 500
        
        if (-not (Test-Path -Path $SourceFile)) {
            return $false
        }
        
        $relativePath = $SourceFile.Substring($Source.Length).TrimStart('\')
        $destFile = Join-Path -Path $Destination -ChildPath $relativePath
        $destFolder = Split-Path -Path $destFile -Parent
        
        if (-not (Test-Path -Path $destFolder)) {
            New-Item -Path $destFolder -ItemType Directory -Force -ErrorAction Stop | Out-Null
            Write-Log -Message "Created folder: $destFolder" -Level "INFO"
        }
        
        if (Test-FileDifferent -SourceFile $SourceFile -DestFile $destFile) {
            # Retry logic for locked files
            $maxRetries = 3
            $retryCount = 0
            $success = $false
            
            while ($retryCount -lt $maxRetries -and -not $success) {
                try {
                    Copy-Item -Path $SourceFile -Destination $destFile -Force -ErrorAction Stop
                    $success = $true
                }
                catch {
                    $retryCount = $retryCount + 1
                    if ($retryCount -lt $maxRetries) {
                        Start-Sleep -Milliseconds 1000
                    }
                    else {
                        throw
                    }
                }
            }
            
            $fileInfo = Get-Item -Path $SourceFile
            $sizeKB = [math]::Round($fileInfo.Length / 1KB, 2)
            Write-Log -Message "SYNCED: $relativePath (Size: $sizeKB KB)" -Level "SUCCESS"
            
            if ($script:ShowNotifications) {
                Show-Notification -Title "File Synced" -Message "$relativePath"
            }
            
            return $true
        }
    }
    catch {
        Write-Log -Message "Failed to sync: $SourceFile - Error: $_" -Level "ERROR"
    }
    
    return $false
}

function Remove-DestinationFile {
    param(
        [string]$SourceFile,
        [string]$Source,
        [string]$Destination
    )
    
    try {
        $relativePath = $SourceFile.Substring($Source.Length).TrimStart('\')
        $destFile = Join-Path -Path $Destination -ChildPath $relativePath
        
        if (Test-Path -Path $destFile) {
            Remove-Item -Path $destFile -Force -ErrorAction Stop
            Write-Log -Message "DELETED: $relativePath" -Level "WARN"
        }
    }
    catch {
        Write-Log -Message "Failed to delete: $SourceFile - Error: $_" -Level "ERROR"
    }
}

function Invoke-InitialSync {
    param(
        [string]$Source,
        [string]$Destination
    )
    
    Write-Log -Message "Starting initial sync scan..." -Level "INFO"
    $syncCount = 0
    
    try {
        $allFiles = Get-ChildItem -Path $Source -Recurse -File -ErrorAction Stop
        
        foreach ($file in $allFiles) {
            $result = Sync-SingleFile -SourceFile $file.FullName -Source $Source -Destination $Destination
            if ($result) { $syncCount = $syncCount + 1 }
        }
        
        Write-Log -Message "Initial sync complete. Files synced: $syncCount" -Level "INFO"
    }
    catch {
        Write-Log -Message "Initial sync failed: $_" -Level "ERROR"
    }
    
    return $syncCount
}

# ============================================================
# Main Execution
# ============================================================

# Clean paths - remove trailing backslashes
$SourceFolder = $SourceFolder.Trim().TrimEnd('\')
$TargetFolder = $TargetFolder.Trim().TrimEnd('\')

Write-Log -Message "==========================================" -Level "INFO"
Write-Log -Message "File Sync Daemon STARTED (PID: $PID)" -Level "INFO"
Write-Log -Message "Source: $SourceFolder" -Level "INFO"
Write-Log -Message "Target: $TargetFolder" -Level "INFO"
Write-Log -Message "Notifications: $script:ShowNotifications" -Level "INFO"
Write-Log -Message "==========================================" -Level "INFO"

# Validate source
if (-not (Test-Path -Path $SourceFolder)) {
    Write-Log -Message "Source folder does not exist: $SourceFolder" -Level "ERROR"
    Show-Notification -Title "Sync Failed" -Message "Source folder not found"
    if (-not [string]::IsNullOrEmpty($PidFilePath) -and (Test-Path -Path $PidFilePath)) {
        Remove-Item -Path $PidFilePath -Force -ErrorAction SilentlyContinue
    }
    exit 1
}

# Create target if not exists
if (-not (Test-Path -Path $TargetFolder)) {
    try {
        New-Item -Path $TargetFolder -ItemType Directory -Force -ErrorAction Stop | Out-Null
        Write-Log -Message "Target folder created: $TargetFolder" -Level "SUCCESS"
    }
    catch {
        Write-Log -Message "Failed to create target folder: $_" -Level "ERROR"
        Show-Notification -Title "Sync Failed" -Message "Cannot create target folder"
        if (-not [string]::IsNullOrEmpty($PidFilePath) -and (Test-Path -Path $PidFilePath)) {
            Remove-Item -Path $PidFilePath -Force -ErrorAction SilentlyContinue
        }
        exit 1
    }
}

# Initial full sync
$initialCount = Invoke-InitialSync -Source $SourceFolder -Destination $TargetFolder
Show-Notification -Title "Sync Service Started" -Message "Watching for changes. Initial sync: $initialCount files"

# ============================================================
# Setup FileSystemWatcher
# ============================================================
$watcher = New-Object System.IO.FileSystemWatcher
$watcher.Path = $SourceFolder
$watcher.IncludeSubdirectories = $true
$watcher.EnableRaisingEvents = $true
$watcher.NotifyFilter = [System.IO.NotifyFilters]::LastWrite -bor `
                       [System.IO.NotifyFilters]::FileName -bor `
                       [System.IO.NotifyFilters]::DirectoryName -bor `
                       [System.IO.NotifyFilters]::Size

Write-Log -Message "FileSystemWatcher active. Monitoring for changes..." -Level "INFO"

# Track recent changes for debouncing
$script:recentChanges = @{}
$script:debounceMs = 1000

# ============================================================
# Main Loop
# ============================================================
$loopCounter = 0

try {
    while ($true) {
        # Check stop signal
        if (-not [string]::IsNullOrEmpty($StopFilePath) -and (Test-Path -Path $StopFilePath)) {
            Write-Log -Message "Stop signal received. Shutting down..." -Level "INFO"
            try { Remove-Item -Path $StopFilePath -Force -ErrorAction SilentlyContinue } catch {}
            break
        }
        
        # Wait for changes (1 second timeout for stop signal check)
        $result = $watcher.WaitForChanged([System.IO.WatcherChangeTypes]::All, 1000)
        
        if (-not $result.TimedOut) {
            $changedPath = Join-Path -Path $SourceFolder -ChildPath $result.Name
            $changeType = $result.ChangeType
            
            # Debounce duplicate events
            $now = Get-Date
            if ($script:recentChanges.ContainsKey($changedPath)) {
                $lastChange = $script:recentChanges[$changedPath]
                $diffMs = ($now - $lastChange).TotalMilliseconds
                if ($diffMs -lt $script:debounceMs) {
                    continue
                }
            }
            $script:recentChanges[$changedPath] = $now
            
            # Clean old debounce entries
            if ($script:recentChanges.Count -gt 100) {
                $cutoff = $now.AddSeconds(-10)
                $keysToRemove = @()
                foreach ($key in $script:recentChanges.Keys) {
                    if ($script:recentChanges[$key] -lt $cutoff) {
                        $keysToRemove += $key
                    }
                }
                foreach ($key in $keysToRemove) {
                    $script:recentChanges.Remove($key)
                }
            }
            
            Write-Log -Message "Event: $changeType - $($result.Name)" -Level "INFO"
            
            switch ($changeType) {
                "Created" {
                    if (Test-Path -Path $changedPath -PathType Leaf) {
                        Sync-SingleFile -SourceFile $changedPath -Source $SourceFolder -Destination $TargetFolder | Out-Null
                    }
                }
                "Changed" {
                    if (Test-Path -Path $changedPath -PathType Leaf) {
                        Sync-SingleFile -SourceFile $changedPath -Source $SourceFolder -Destination $TargetFolder | Out-Null
                    }
                }
                "Deleted" {
                    Remove-DestinationFile -SourceFile $changedPath -Source $SourceFolder -Destination $TargetFolder
                }
                "Renamed" {
                    if (Test-Path -Path $changedPath -PathType Leaf) {
                        Sync-SingleFile -SourceFile $changedPath -Source $SourceFolder -Destination $TargetFolder | Out-Null
                    }
                }
            }
        }
        
        # Heartbeat every 5 minutes
        $loopCounter = $loopCounter + 1
        if ($loopCounter -ge 300) {
            Write-Log -Message "Heartbeat: daemon alive and watching" -Level "INFO"
            $loopCounter = 0
        }
    }
}
catch {
    Write-Log -Message "Daemon crashed: $_" -Level "ERROR"
    Show-Notification -Title "Sync Service Crashed" -Message "Check logs for details"
}
finally {
    # Cleanup
    if ($watcher) {
        $watcher.EnableRaisingEvents = $false
        $watcher.Dispose()
    }
    
    if (-not [string]::IsNullOrEmpty($PidFilePath) -and (Test-Path -Path $PidFilePath)) {
        try { Remove-Item -Path $PidFilePath -Force -ErrorAction SilentlyContinue } catch {}
    }
    
    Write-Log -Message "==========================================" -Level "INFO"
    Write-Log -Message "File Sync Daemon STOPPED" -Level "INFO"
    Write-Log -Message "==========================================" -Level "INFO"
    
    Show-Notification -Title "Sync Service Stopped" -Message "Background sync has been terminated"
}

exit 0