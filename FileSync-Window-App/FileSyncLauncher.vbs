' ============================================================
' File Sync Control Panel
' Author: Abhishek Singh
' Purpose: Start / Stop / Manage the background sync daemon
' ============================================================

Option Explicit

Dim objShell, objFSO, scriptPath, psScriptPath
Dim configFilePath, pidFilePath, stopFilePath, logFilePath
Dim savedSource, savedTarget, savedNotifications

Set objShell = CreateObject("WScript.Shell")
Set objFSO = CreateObject("Scripting.FileSystemObject")

scriptPath = objFSO.GetParentFolderName(WScript.ScriptFullName)
psScriptPath = scriptPath & "\FileSync.ps1"
configFilePath = scriptPath & "\FileSyncConfig.ini"
pidFilePath = scriptPath & "\FileSync.pid"
stopFilePath = scriptPath & "\FileSync.stop"
logFilePath = objShell.ExpandEnvironmentStrings("%USERPROFILE%") & "\FileSyncLogs\FileSyncDaemon.log"

' Defaults
savedSource = "D:\as7.workspace\Nagarro-Hackathon\team-vikings"
savedTarget = "\\tf-fileserver.thinkfoliohosted.com\share\Users\as7.network\team-vikings"
savedNotifications = "False"

' Validate PS1 exists
If Not objFSO.FileExists(psScriptPath) Then
    MsgBox "PowerShell script not found:" & vbCrLf & psScriptPath, vbCritical, "File Sync - Error"
    WScript.Quit
End If

' Load config if exists
If objFSO.FileExists(configFilePath) Then LoadConfig()

' Show main menu
ShowMainMenu()

' ============================================================
' Main Menu
' ============================================================
Sub ShowMainMenu()
    Dim menuMsg, choice, isRunning, statusText
    
    Do
        isRunning = IsSyncRunning()
        
        If isRunning Then
            statusText = "RUNNING (PID: " & GetSyncPid() & ")"
        Else
            statusText = "STOPPED"
        End If
        
        menuMsg = "===== FILE SYNC CONTROL PANEL =====" & vbCrLf & vbCrLf & _
                  "Status: " & statusText & vbCrLf & vbCrLf & _
                  "Source: " & savedSource & vbCrLf & _
                  "Target: " & savedTarget & vbCrLf & vbCrLf & _
                  "Choose an action:" & vbCrLf & vbCrLf & _
                  "  1 - Start Sync Service" & vbCrLf & _
                  "  2 - Stop Sync Service" & vbCrLf & _
                  "  3 - View Log File" & vbCrLf & _
                  "  4 - Change Settings" & vbCrLf & _
                  "  5 - View Status" & vbCrLf & _
                  "  0 - Exit Control Panel" & vbCrLf & vbCrLf & _
                  "Enter your choice (0-5):"
        
        choice = InputBox(menuMsg, "File Sync Control Panel", "1")
        
        If choice = "" Then Exit Sub
        
        choice = Trim(choice)
        
        Select Case choice
            Case "1"
                StartSyncService()
            Case "2"
                StopSyncService()
            Case "3"
                ViewLogFile()
            Case "4"
                ChangeSettings()
            Case "5"
                ShowStatus()
            Case "0"
                Exit Sub
            Case Else
                MsgBox "Invalid choice. Please enter a number between 0 and 5.", vbExclamation, "File Sync"
        End Select
    Loop
End Sub

' ============================================================
' Start the sync daemon
' ============================================================
Sub StartSyncService()
    If IsSyncRunning() Then
        MsgBox "Sync service is already running (PID: " & GetSyncPid() & ")" & vbCrLf & vbCrLf & _
               "Stop it first if you want to restart with new settings.", _
               vbInformation, "File Sync - Already Running"
        Exit Sub
    End If
    
    ' First-time setup if no config
    If Not objFSO.FileExists(configFilePath) Then
        If MsgBox("No settings found. Configure now?", vbQuestion + vbYesNo, "File Sync") = vbYes Then
            ChangeSettings()
            If Not objFSO.FileExists(configFilePath) Then Exit Sub
        Else
            Exit Sub
        End If
    End If
    
    ' Sanitize paths - remove trailing backslashes
    savedSource = CleanPath(savedSource)
    savedTarget = CleanPath(savedTarget)
    
    ' Validate source
    If Not objFSO.FolderExists(savedSource) Then
        MsgBox "Source folder does not exist:" & vbCrLf & savedSource & vbCrLf & vbCrLf & _
               "Please update settings.", vbExclamation, "File Sync"
        Exit Sub
    End If
    
    ' Ensure log folder exists
    Dim logFolderPath
    logFolderPath = objFSO.GetParentFolderName(logFilePath)
    If Not objFSO.FolderExists(logFolderPath) Then
        CreateFolderRecursive(logFolderPath)
    End If
    
    ' Clean up any leftover files
    If objFSO.FileExists(stopFilePath) Then objFSO.DeleteFile stopFilePath, True
    If objFSO.FileExists(pidFilePath) Then objFSO.DeleteFile pidFilePath, True
    
    ' Build command
    Dim psCommand
    psCommand = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & psScriptPath & """" & _
                " -SourceFolder """ & savedSource & """" & _
                " -TargetFolder """ & savedTarget & """" & _
                " -ShowNotifications """ & savedNotifications & """" & _
                " -LogFilePath """ & logFilePath & """" & _
                " -PidFilePath """ & pidFilePath & """" & _
                " -StopFilePath """ & stopFilePath & """"
    
    ' Launch hidden, non-blocking
    objShell.Run psCommand, 0, False
    
    ' Wait for PID file (up to 15 seconds)
    Dim waitCount
    waitCount = 0
    Do While Not objFSO.FileExists(pidFilePath) And waitCount < 60
        WScript.Sleep 250
        waitCount = waitCount + 1
    Loop
    
    If objFSO.FileExists(pidFilePath) Then
        MsgBox "Sync service started successfully!" & vbCrLf & vbCrLf & _
               "PID: " & GetSyncPid() & vbCrLf & _
               "Status: Running in background" & vbCrLf & vbCrLf & _
               "The service will now monitor your source folder for changes" & vbCrLf & _
               "and sync them automatically to the target." & vbCrLf & vbCrLf & _
               "Log file: " & logFilePath, _
               vbInformation, "File Sync - Started"
    Else
        Dim errorMsg
        errorMsg = "Sync service failed to start." & vbCrLf & vbCrLf
        
        If objFSO.FileExists(logFilePath) Then
            errorMsg = errorMsg & "Log file exists. Open it to see the error?"
            If MsgBox(errorMsg, vbExclamation + vbYesNo, "File Sync - Failed") = vbYes Then
                objShell.Run "notepad++.exe """ & logFilePath & """", 1, False
            End If
        Else
            errorMsg = errorMsg & "Log file was not created. PowerShell likely failed to launch." & vbCrLf & _
                       "Check that PowerShell execution policy allows scripts."
            MsgBox errorMsg, vbExclamation, "File Sync - Failed"
        End If
    End If
End Sub

' ============================================================
' Stop the sync daemon
' ============================================================
Sub StopSyncService()
    If Not IsSyncRunning() Then
        MsgBox "Sync service is not running.", vbInformation, "File Sync"
        Exit Sub
    End If
    
    Dim pidValue
    pidValue = GetSyncPid()
    
    If MsgBox("Are you sure you want to stop the sync service?" & vbCrLf & vbCrLf & _
              "PID: " & pidValue & vbCrLf & _
              "Any pending file changes may not be synced.", _
              vbQuestion + vbYesNo, "File Sync - Confirm Stop") = vbNo Then
        Exit Sub
    End If
    
    ' Create stop signal
    Dim stopFile
    Set stopFile = objFSO.CreateTextFile(stopFilePath, True)
    stopFile.WriteLine "stop"
    stopFile.Close
    Set stopFile = Nothing
    
    ' Wait for graceful stop (up to 10 seconds)
    Dim waitCount
    waitCount = 0
    Do While objFSO.FileExists(pidFilePath) And waitCount < 40
        WScript.Sleep 250
        waitCount = waitCount + 1
    Loop
    
    ' Force kill if needed
    If objFSO.FileExists(pidFilePath) Then
        If MsgBox("Graceful stop failed. Force kill the process?", vbQuestion + vbYesNo, "File Sync") = vbYes Then
            objShell.Run "taskkill /F /PID " & pidValue, 0, True
            WScript.Sleep 500
            If objFSO.FileExists(pidFilePath) Then objFSO.DeleteFile pidFilePath, True
            If objFSO.FileExists(stopFilePath) Then objFSO.DeleteFile stopFilePath, True
            MsgBox "Sync service forcefully terminated.", vbInformation, "File Sync"
        End If
    Else
        MsgBox "Sync service stopped successfully.", vbInformation, "File Sync - Stopped"
    End If
End Sub

' ============================================================
' View log file
' ============================================================
Sub ViewLogFile()
    If Not objFSO.FileExists(logFilePath) Then
        MsgBox "Log file does not exist yet:" & vbCrLf & logFilePath & vbCrLf & vbCrLf & _
               "Start the sync service first.", vbInformation, "File Sync"
        Exit Sub
    End If
    
    objShell.Run "notepad++.exe """ & logFilePath & """", 1, False
End Sub

' ============================================================
' Change settings
' ============================================================
Sub ChangeSettings()
    If IsSyncRunning() Then
        If MsgBox("Sync service is running. Settings changes will only take effect after restart." & vbCrLf & vbCrLf & _
                  "Continue with settings change?", vbQuestion + vbYesNo, "File Sync") = vbNo Then
            Exit Sub
        End If
    End If
    
    Dim newSource, newTarget, response
    
    ' Source
    Do
        newSource = InputBox("Enter SOURCE folder path:", "Settings - Source Folder", savedSource)
        If newSource = "" Then Exit Sub
        newSource = CleanPath(newSource)
        If Not objFSO.FolderExists(newSource) Then
            MsgBox "Folder does not exist: " & newSource, vbExclamation, "File Sync"
            newSource = ""
        End If
    Loop Until newSource <> ""
    
    ' Target
    Do
        newTarget = InputBox("Enter TARGET folder path:", "Settings - Target Folder", savedTarget)
        If newTarget = "" Then Exit Sub
        newTarget = CleanPath(newTarget)
        If Len(newTarget) < 3 Then
            MsgBox "Path too short.", vbExclamation, "File Sync"
            newTarget = ""
        ElseIf LCase(newTarget) = LCase(newSource) Then
            MsgBox "Target cannot be same as source.", vbExclamation, "File Sync"
            newTarget = ""
        End If
    Loop Until newTarget <> ""
    
    ' Notifications
    response = MsgBox("Show notification for each file synced?" & vbCrLf & vbCrLf & _
                      "YES - Notify every file (verbose)" & vbCrLf & _
                      "NO  - Silent (recommended)", _
                      vbQuestion + vbYesNo, "Settings - Notifications")
    
    savedSource = newSource
    savedTarget = newTarget
    If response = vbYes Then
        savedNotifications = "True"
    Else
        savedNotifications = "False"
    End If
    
    SaveConfig()
    
    MsgBox "Settings saved successfully!" & vbCrLf & vbCrLf & _
           "Source: " & savedSource & vbCrLf & _
           "Target: " & savedTarget & vbCrLf & _
           "Notifications: " & savedNotifications, _
           vbInformation, "File Sync - Settings Saved"
End Sub

' ============================================================
' Show detailed status
' ============================================================
Sub ShowStatus()
    Dim statusMsg, isRunning
    isRunning = IsSyncRunning()
    
    statusMsg = "===== SYNC SERVICE STATUS =====" & vbCrLf & vbCrLf
    
    If isRunning Then
        statusMsg = statusMsg & "Service State: RUNNING" & vbCrLf
        statusMsg = statusMsg & "Process ID:    " & GetSyncPid() & vbCrLf
    Else
        statusMsg = statusMsg & "Service State: STOPPED" & vbCrLf
    End If
    
    statusMsg = statusMsg & vbCrLf & "Configuration:" & vbCrLf
    statusMsg = statusMsg & "  Source: " & savedSource & vbCrLf
    statusMsg = statusMsg & "  Target: " & savedTarget & vbCrLf
    statusMsg = statusMsg & "  Notifications: " & savedNotifications & vbCrLf
    statusMsg = statusMsg & vbCrLf & "Log File:" & vbCrLf & "  " & logFilePath
    
    MsgBox statusMsg, vbInformation, "File Sync - Status"
End Sub

' ============================================================
' Check if sync daemon is running
' ============================================================
Function IsSyncRunning()
    IsSyncRunning = False
    
    If Not objFSO.FileExists(pidFilePath) Then Exit Function
    
    Dim pidValue
    pidValue = GetSyncPid()
    
    If pidValue = "" Then Exit Function
    
    ' Verify process exists via WMI
    Dim wmi, processes, proc
    On Error Resume Next
    Set wmi = GetObject("winmgmts:\\.\root\cimv2")
    Set processes = wmi.ExecQuery("Select ProcessId from Win32_Process where ProcessId=" & pidValue)
    
    If Err.Number = 0 Then
        For Each proc In processes
            IsSyncRunning = True
            Exit For
        Next
    End If
    
    ' Cleanup stale PID file
    If Not IsSyncRunning Then
        On Error Resume Next
        objFSO.DeleteFile pidFilePath, True
    End If
    
    On Error Goto 0
End Function

' ============================================================
' Get PID from file
' ============================================================
Function GetSyncPid()
    GetSyncPid = ""
    If Not objFSO.FileExists(pidFilePath) Then Exit Function
    
    On Error Resume Next
    Dim pidFile, pidValue
    Set pidFile = objFSO.OpenTextFile(pidFilePath, 1)
    If Err.Number = 0 Then
        pidValue = Trim(pidFile.ReadAll)
        pidFile.Close
        GetSyncPid = pidValue
    End If
    On Error Goto 0
End Function

' ============================================================
' Clean path - remove trailing backslashes and quotes
' ============================================================
Function CleanPath(pathStr)
    Dim result
    result = Trim(pathStr)
    result = Replace(result, Chr(34), "")
    
    ' Remove trailing backslashes (critical for PowerShell command line)
    Do While Right(result, 1) = "\" And Len(result) > 3
        result = Left(result, Len(result) - 1)
    Loop
    
    CleanPath = result
End Function

' ============================================================
' Create folder recursively
' ============================================================
Sub CreateFolderRecursive(folderPath)
    If objFSO.FolderExists(folderPath) Then Exit Sub
    Dim parentPath
    parentPath = objFSO.GetParentFolderName(folderPath)
    If parentPath <> "" And Not objFSO.FolderExists(parentPath) Then
        CreateFolderRecursive(parentPath)
    End If
    On Error Resume Next
    objFSO.CreateFolder(folderPath)
    On Error Goto 0
End Sub

' ============================================================
' Save config
' ============================================================
Sub SaveConfig()
    Dim configFile
    On Error Resume Next
    Set configFile = objFSO.CreateTextFile(configFilePath, True)
    If Err.Number <> 0 Then Exit Sub
    On Error Goto 0
    
    configFile.WriteLine "[FileSyncSettings]"
    configFile.WriteLine "SourceFolder=" & savedSource
    configFile.WriteLine "TargetFolder=" & savedTarget
    configFile.WriteLine "ShowNotifications=" & savedNotifications
    configFile.Close
    Set configFile = Nothing
End Sub

' ============================================================
' Load config
' ============================================================
Sub LoadConfig()
    Dim configFile, line, parts
    On Error Resume Next
    Set configFile = objFSO.OpenTextFile(configFilePath, 1)
    If Err.Number <> 0 Then Exit Sub
    On Error Goto 0
    
    Do While Not configFile.AtEndOfStream
        line = Trim(configFile.ReadLine)
        If line <> "" And Left(line, 1) <> "[" Then
            If InStr(line, "=") > 0 Then
                parts = Split(line, "=", 2)
                Select Case Trim(parts(0))
                    Case "SourceFolder"
                        savedSource = CleanPath(Trim(parts(1)))
                    Case "TargetFolder"
                        savedTarget = CleanPath(Trim(parts(1)))
                    Case "ShowNotifications"
                        savedNotifications = Trim(parts(1))
                End Select
            End If
        End If
    Loop
    
    configFile.Close
    Set configFile = Nothing
End Sub