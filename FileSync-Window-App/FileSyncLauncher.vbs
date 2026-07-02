' ============================================================
' File Sync Control Panel (Multi-Profile Support)
' Author: Abhishek Singh
' ============================================================

Option Explicit

Dim objShell, objFSO, scriptPath, psScriptPath, profilesRoot, logsRoot
Dim currentProfile, profilePath
Dim configFilePath, pidFilePath, stopFilePath, logFilePath
Dim savedSource, savedTarget, savedNotifications

Set objShell = CreateObject("WScript.Shell")
Set objFSO = CreateObject("Scripting.FileSystemObject")

scriptPath = objFSO.GetParentFolderName(WScript.ScriptFullName)
psScriptPath = scriptPath & "\FileSync.ps1"
profilesRoot = scriptPath & "\Profiles"
logsRoot = objShell.ExpandEnvironmentStrings("%USERPROFILE%") & "\FileSyncLogs"

' Validate PS1 exists
If Not objFSO.FileExists(psScriptPath) Then
    MsgBox "PowerShell script not found:" & vbCrLf & psScriptPath, vbCritical, "File Sync - Error"
    WScript.Quit
End If

' Ensure Profiles folder exists
If Not objFSO.FolderExists(profilesRoot) Then objFSO.CreateFolder(profilesRoot)
If Not objFSO.FolderExists(logsRoot) Then objFSO.CreateFolder(logsRoot)

' Select or create a profile
If Not SelectProfile() Then WScript.Quit

' Load selected profile config
If objFSO.FileExists(configFilePath) Then LoadConfig()

' Show main menu
ShowMainMenu()

' ============================================================
' Profile Selection
' ============================================================
Function SelectProfile()
    SelectProfile = False
    
    Dim profiles, profileList, i, choice, folder
    profileList = ""
    i = 0
    ReDim profiles(100)
    
    ' List existing profiles
    Dim profileFolder
    Set profileFolder = objFSO.GetFolder(profilesRoot)
    For Each folder In profileFolder.SubFolders
        profiles(i) = folder.Name
        profileList = profileList & "  " & (i + 1) & " - " & folder.Name & vbCrLf
        i = i + 1
    Next
    
    Dim menuMsg
    menuMsg = "===== SELECT SYNC PROFILE =====" & vbCrLf & vbCrLf
    
    If i = 0 Then
        menuMsg = menuMsg & "No profiles found yet." & vbCrLf & vbCrLf
    Else
        menuMsg = menuMsg & "Existing profiles:" & vbCrLf & profileList & vbCrLf
    End If
    
    menuMsg = menuMsg & "  N - Create NEW profile" & vbCrLf & _
              "  0 - Exit" & vbCrLf & vbCrLf & _
              "Enter profile number, 'N' for new, or '0' to exit:"
    
    choice = InputBox(menuMsg, "File Sync - Profile Selection", "1")
    
    If choice = "" Or choice = "0" Then Exit Function
    
    choice = Trim(UCase(choice))
    
    If choice = "N" Then
        Dim newName
        newName = InputBox("Enter a name for the new profile (letters, numbers, hyphens only):" & vbCrLf & vbCrLf & _
                           "Examples: Work, Personal, Project-Alpha", _
                           "New Profile", "Profile1")
        
        If newName = "" Then Exit Function
        
        newName = Trim(newName)
        
        ' Sanitize name
        If Not IsValidProfileName(newName) Then
            MsgBox "Invalid profile name. Use only letters, numbers, and hyphens.", vbExclamation, "File Sync"
            Exit Function
        End If
        
        If objFSO.FolderExists(profilesRoot & "\" & newName) Then
            MsgBox "Profile already exists: " & newName, vbExclamation, "File Sync"
            Exit Function
        End If
        
        objFSO.CreateFolder(profilesRoot & "\" & newName)
        currentProfile = newName
    Else
        Dim idx
        If Not IsNumeric(choice) Then
            MsgBox "Invalid choice.", vbExclamation, "File Sync"
            Exit Function
        End If
        
        idx = CInt(choice) - 1
        If idx < 0 Or idx >= i Then
            MsgBox "Invalid profile number.", vbExclamation, "File Sync"
            Exit Function
        End If
        
        currentProfile = profiles(idx)
    End If
    
    ' Set paths for this profile
    profilePath = profilesRoot & "\" & currentProfile
    configFilePath = profilePath & "\config.ini"
    pidFilePath = profilePath & "\sync.pid"
    stopFilePath = profilePath & "\sync.stop"
    logFilePath = logsRoot & "\" & currentProfile & ".log"
    
    ' Defaults
    savedSource = ""
    savedTarget = ""
    savedNotifications = "False"
    
    SelectProfile = True
End Function

Function IsValidProfileName(name)
    Dim i, ch
    IsValidProfileName = False
    If Len(name) = 0 Or Len(name) > 50 Then Exit Function
    
    For i = 1 To Len(name)
        ch = Mid(name, i, 1)
        If Not ((ch >= "a" And ch <= "z") Or (ch >= "A" And ch <= "Z") Or _
                (ch >= "0" And ch <= "9") Or ch = "-" Or ch = "_") Then
            Exit Function
        End If
    Next
    
    IsValidProfileName = True
End Function

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
        
        menuMsg = "===== FILE SYNC: " & currentProfile & " =====" & vbCrLf & vbCrLf & _
                  "Status: " & statusText & vbCrLf & vbCrLf & _
                  "Source: " & savedSource & vbCrLf & _
                  "Target: " & savedTarget & vbCrLf & vbCrLf & _
                  "Choose an action:" & vbCrLf & vbCrLf & _
                  "  1 - Start Sync Service" & vbCrLf & _
                  "  2 - Stop Sync Service" & vbCrLf & _
                  "  3 - View Log File" & vbCrLf & _
                  "  4 - Change Settings" & vbCrLf & _
                  "  5 - View Status" & vbCrLf & _
                  "  6 - Switch Profile" & vbCrLf & _
                  "  0 - Exit Control Panel" & vbCrLf & vbCrLf & _
                  "Enter your choice:"
        
        choice = InputBox(menuMsg, "File Sync - " & currentProfile, "1")
        
        If choice = "" Then Exit Sub
        choice = Trim(choice)
        
        Select Case choice
            Case "1" : StartSyncService()
            Case "2" : StopSyncService()
            Case "3" : ViewLogFile()
            Case "4" : ChangeSettings()
            Case "5" : ShowStatus()
            Case "6"
                If SelectProfile() Then
                    If objFSO.FileExists(configFilePath) Then LoadConfig()
                Else
                    Exit Sub
                End If
            Case "0" : Exit Sub
            Case Else : MsgBox "Invalid choice.", vbExclamation, "File Sync"
        End Select
    Loop
End Sub

' ============================================================
' Start Sync Service
' ============================================================
Sub StartSyncService()
    If IsSyncRunning() Then
        MsgBox "Sync service for profile '" & currentProfile & "' is already running." & vbCrLf & _
               "PID: " & GetSyncPid(), vbInformation, "File Sync"
        Exit Sub
    End If
    
    If Not objFSO.FileExists(configFilePath) Then
        If MsgBox("Profile not configured yet. Configure now?", vbQuestion + vbYesNo, "File Sync") = vbYes Then
            ChangeSettings()
            If Not objFSO.FileExists(configFilePath) Then Exit Sub
        Else
            Exit Sub
        End If
    End If
    
    savedSource = CleanPath(savedSource)
    savedTarget = CleanPath(savedTarget)
    
    If Not objFSO.FolderExists(savedSource) Then
        MsgBox "Source folder does not exist:" & vbCrLf & savedSource, vbExclamation, "File Sync"
        Exit Sub
    End If
    
    ' Clean up any leftover files
    If objFSO.FileExists(stopFilePath) Then objFSO.DeleteFile stopFilePath, True
    If objFSO.FileExists(pidFilePath) Then objFSO.DeleteFile pidFilePath, True
    
    Dim psCommand
    psCommand = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & psScriptPath & """" & _
                " -SourceFolder """ & savedSource & """" & _
                " -TargetFolder """ & savedTarget & """" & _
                " -ShowNotifications """ & savedNotifications & """" & _
                " -LogFilePath """ & logFilePath & """" & _
                " -PidFilePath """ & pidFilePath & """" & _
                " -StopFilePath """ & stopFilePath & """"
    
    objShell.Run psCommand, 0, False
    
    Dim waitCount
    waitCount = 0
    Do While Not objFSO.FileExists(pidFilePath) And waitCount < 60
        WScript.Sleep 250
        waitCount = waitCount + 1
    Loop
    
    If objFSO.FileExists(pidFilePath) Then
        MsgBox "Sync service started for profile: " & currentProfile & vbCrLf & vbCrLf & _
               "PID: " & GetSyncPid() & vbCrLf & _
               "Log: " & logFilePath, vbInformation, "File Sync - Started"
    Else
        MsgBox "Sync service failed to start. Check log: " & logFilePath, vbExclamation, "File Sync"
    End If
End Sub

' ============================================================
' Stop Sync Service
' ============================================================
Sub StopSyncService()
    If Not IsSyncRunning() Then
        MsgBox "Sync service for profile '" & currentProfile & "' is not running.", vbInformation, "File Sync"
        Exit Sub
    End If
    
    Dim pidValue
    pidValue = GetSyncPid()
    
    If MsgBox("Stop sync service for profile '" & currentProfile & "'?" & vbCrLf & _
              "PID: " & pidValue, vbQuestion + vbYesNo, "File Sync") = vbNo Then
        Exit Sub
    End If
    
    Dim stopFile
    Set stopFile = objFSO.CreateTextFile(stopFilePath, True)
    stopFile.WriteLine "stop"
    stopFile.Close
    Set stopFile = Nothing
    
    Dim waitCount
    waitCount = 0
    Do While objFSO.FileExists(pidFilePath) And waitCount < 40
        WScript.Sleep 250
        waitCount = waitCount + 1
    Loop
    
    If objFSO.FileExists(pidFilePath) Then
        If MsgBox("Graceful stop failed. Force kill?", vbQuestion + vbYesNo, "File Sync") = vbYes Then
            objShell.Run "taskkill /F /PID " & pidValue, 0, True
            WScript.Sleep 500
            If objFSO.FileExists(pidFilePath) Then objFSO.DeleteFile pidFilePath, True
            If objFSO.FileExists(stopFilePath) Then objFSO.DeleteFile stopFilePath, True
            MsgBox "Sync service forcefully terminated.", vbInformation, "File Sync"
        End If
    Else
        MsgBox "Sync service stopped: " & currentProfile, vbInformation, "File Sync"
    End If
End Sub

' ============================================================
' View Log File
' ============================================================
Sub ViewLogFile()
    If Not objFSO.FileExists(logFilePath) Then
        MsgBox "Log file does not exist yet:" & vbCrLf & logFilePath, vbInformation, "File Sync"
        Exit Sub
    End If
    objShell.Run "notepad.exe """ & logFilePath & """", 1, False
End Sub

' ============================================================
' Change Settings
' ============================================================
Sub ChangeSettings()
    If IsSyncRunning() Then
        If MsgBox("Service is running. Changes take effect after restart. Continue?", _
                  vbQuestion + vbYesNo, "File Sync") = vbNo Then Exit Sub
    End If
    
    Dim newSource, newTarget, response
    
    Do
        newSource = InputBox("Enter SOURCE folder for profile '" & currentProfile & "':", _
                             "Settings - Source", savedSource)
        If newSource = "" Then Exit Sub
        newSource = CleanPath(newSource)
        If Not objFSO.FolderExists(newSource) Then
            MsgBox "Folder does not exist: " & newSource, vbExclamation, "File Sync"
            newSource = ""
        End If
    Loop Until newSource <> ""
    
    Do
        newTarget = InputBox("Enter TARGET folder for profile '" & currentProfile & "':", _
                             "Settings - Target", savedTarget)
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
    
    response = MsgBox("Show notification for each file synced?", vbQuestion + vbYesNo, "Settings")
    
    savedSource = newSource
    savedTarget = newTarget
    If response = vbYes Then savedNotifications = "True" Else savedNotifications = "False"
    
    SaveConfig()
    MsgBox "Settings saved for profile: " & currentProfile, vbInformation, "File Sync"
End Sub

' ============================================================
' Show Status
' ============================================================
Sub ShowStatus()
    Dim statusMsg
    statusMsg = "===== PROFILE: " & currentProfile & " =====" & vbCrLf & vbCrLf
    
    If IsSyncRunning() Then
        statusMsg = statusMsg & "State: RUNNING" & vbCrLf & "PID: " & GetSyncPid() & vbCrLf
    Else
        statusMsg = statusMsg & "State: STOPPED" & vbCrLf
    End If
    
    statusMsg = statusMsg & vbCrLf & "Source: " & savedSource & vbCrLf & _
                "Target: " & savedTarget & vbCrLf & _
                "Notifications: " & savedNotifications & vbCrLf & vbCrLf & _
                "Log: " & logFilePath
    
    MsgBox statusMsg, vbInformation, "File Sync - Status"
End Sub

' ============================================================
' Utility Functions
' ============================================================
Function IsSyncRunning()
    IsSyncRunning = False
    If Not objFSO.FileExists(pidFilePath) Then Exit Function
    
    Dim pidValue
    pidValue = GetSyncPid()
    If pidValue = "" Then Exit Function
    
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
    
    If Not IsSyncRunning Then
        On Error Resume Next
        objFSO.DeleteFile pidFilePath, True
    End If
    On Error Goto 0
End Function

Function GetSyncPid()
    GetSyncPid = ""
    If Not objFSO.FileExists(pidFilePath) Then Exit Function
    
    On Error Resume Next
    Dim pidFile
    Set pidFile = objFSO.OpenTextFile(pidFilePath, 1)
    If Err.Number = 0 Then
        GetSyncPid = Trim(pidFile.ReadAll)
        pidFile.Close
    End If
    On Error Goto 0
End Function

Function CleanPath(pathStr)
    Dim result
    result = Trim(pathStr)
    result = Replace(result, Chr(34), "")
    Do While Right(result, 1) = "\" And Len(result) > 3
        result = Left(result, Len(result) - 1)
    Loop
    CleanPath = result
End Function

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
End Sub

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
                    Case "SourceFolder"      : savedSource = CleanPath(Trim(parts(1)))
                    Case "TargetFolder"      : savedTarget = CleanPath(Trim(parts(1)))
                    Case "ShowNotifications" : savedNotifications = Trim(parts(1))
                End Select
            End If
        End If
    Loop
    configFile.Close
End Sub