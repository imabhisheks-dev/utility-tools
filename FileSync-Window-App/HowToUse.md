# File Sync Utility - How to Use

A lightweight background file sync tool for Windows. Monitors a source folder and auto-syncs changes to a target folder in real-time (like OneDrive).

## Prerequisites

- Windows 7 or later
- PowerShell 2.0+
- Read access on source, write access on target

## Files

| File | Purpose |
|------|---------|
| `FileSyncLauncher.vbs` | Control panel UI (start/stop/manage) |
| `FileSync.ps1` | Background sync daemon |
| `FileSyncConfig.ini` | Auto-generated settings file |

> Both `.vbs` and `.ps1` must be in the **same folder**.

## Installation

1. Place `FileSyncLauncher.vbs` and `FileSync.ps1` in the same folder.
2. Enable PowerShell scripts (one-time, run PowerShell as Admin):
   ```powershell
   Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
   ```

## Quick Start

1. Double-click `FileSyncLauncher.vbs`.
2. Enter `1` to start the sync service.
3. First run only: enter source folder, target folder, notification preference.
4. Service starts in background and syncs immediately.

## Control Panel Menu

| Option | Action |
|--------|--------|
| 1 | Start sync service |
| 2 | Stop sync service |
| 3 | View log file |
| 4 | Change settings |
| 5 | View current status |
| 0 | Exit control panel (service keeps running) |

> Closing the control panel does **not** stop the sync. Use option `2` to stop.

## Configuration

File: `FileSyncConfig.ini` (auto-created next to VBS)

```ini
[FileSyncSettings]
SourceFolder=D:\MyProject
TargetFolder=\\server\share\backup
ShowNotifications=False
```

**Rules:**
- No trailing backslashes in paths
- Target must be different from source
- `ShowNotifications` = `True` or `False`

To reset config: delete the `.ini` file.

## Sync Behavior

| Event in Source | Action in Target |
|-----------------|------------------|
| File created | Copied |
| File modified (size or timestamp differs) | Overwritten |
| File deleted | Deleted |
| File renamed | Copied with new name |
| Subfolder created | Created on demand |

**Sync is one-way only** (source → target).

## Logs

**Location:** `%USERPROFILE%\FileSyncLogs\FileSyncDaemon.log`

**Format:** `[YYYY-MM-DD HH:MM:SS] [LEVEL] Message`

**Levels:** `INFO`, `SUCCESS`, `WARN`, `ERROR`, `STARTUP`

**Sample:**
```
[2026-07-02 09:15:23] [INFO] File Sync Daemon STARTED (PID: 12345)
[2026-07-02 09:15:26] [SUCCESS] SYNCED: src\app.js (Size: 12.45 KB)
[2026-07-02 09:18:45] [INFO] Event: Changed - src\app.js
[2026-07-02 09:20:23] [INFO] Heartbeat: daemon alive and watching
```

## Runtime Files

Auto-managed in the app folder:

| File | Meaning |
|------|---------|
| `FileSync.pid` | Present = daemon running |
| `FileSync.stop` | Signal file to stop daemon (auto-created/deleted) |

Do not edit these manually.

## Testing (For QA)

### Test 1: Basic sync
1. Start service.
2. Create `test.txt` in source folder.
3. **Expected:** File appears in target within 2 seconds. Log shows `SYNCED: test.txt`.

### Test 2: Modification sync
1. Modify `test.txt` (change content, save).
2. **Expected:** Target file updates. Log shows `Event: Changed` then `SYNCED`.

### Test 3: Deletion sync
1. Delete `test.txt` from source.
2. **Expected:** Target file removed. Log shows `DELETED: test.txt`.

### Test 4: Subfolder sync
1. Create `newfolder\file.txt` in source.
2. **Expected:** Subfolder and file appear in target.

### Test 5: Graceful stop
1. From control panel, select option `2`.
2. Confirm stop.
3. **Expected:** PID file removed, service status shows STOPPED.

### Test 6: Restart persistence
1. Stop service.
2. Restart control panel.
3. **Expected:** Settings retained from previous session.

### Test 7: Invalid source
1. Change settings to non-existent source folder.
2. Try to start.
3. **Expected:** Error dialog "Source folder does not exist".

### Test 8: Network target
1. Configure target as UNC path.
2. Start service and modify a file.
3. **Expected:** File synced to network location.

## Troubleshooting

### Service fails to start
Run PowerShell manually to see the actual error:
```cmd
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "<path>\FileSync.ps1" -SourceFolder "<src>" -TargetFolder "<tgt>" -ShowNotifications "False"
```

### Common errors

| Error | Fix |
|-------|-----|
| Execution policy blocked | Run `Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned` |
| Source folder does not exist | Update settings (option 4), verify path |
| Cannot create target folder | Check permissions/network connectivity |
| Parameter transformation error | Ensure paths have no trailing backslashes |

### Log file not created
- Verify `%USERPROFILE%\FileSyncLogs\` folder is writable.
- Check `%TEMP%\FileSync_CRITICAL_ERROR.log` for fallback errors.

### Service won't stop gracefully
- Control panel option `2` will offer force-kill after 10 seconds.
- Manual kill: `taskkill /F /PID <PID>` (PID from `FileSync.pid`).

### Files not syncing
1. Check status (option 5) — must be RUNNING.
2. Check log for ERROR entries.
3. Verify write permissions on target.

## Performance

| Metric | Value |
|--------|-------|
| CPU (idle) | ~0% |
| CPU (during sync) | Brief spike |
| RAM | 30-50 MB |
| Sync latency | 0.5-2 seconds |

## Known Limitations

- One-way sync only (no two-way/conflict resolution)
- No file exclusion filters (all files synced)
- Not a Windows Service (runs as user process, stops on logoff)
- No sync queue for offline targets — failed syncs are logged but not retried
- NTFS permissions not preserved (target inherits parent folder ACL)

## Auto-Start on Login (Optional)

1. Press `Win + R`, type `shell:startup`, press Enter.
2. Create shortcut to `FileSyncLauncher.vbs` in that folder.

## Uninstall

1. Stop service (option 2).
2. Delete app folder.
3. Delete `%USERPROFILE%\FileSyncLogs\` (optional).

## Support

**Author:** Abhishek Singh  
**Email:** standalone.abhishek@gmail.com  
**Team:** IT - Application Development