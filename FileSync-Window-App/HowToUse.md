# File Sync Utility - How to Use

A lightweight background file sync tool for Windows with multi-profile support. Monitors source folders and auto-syncs changes to target folders in real-time (like OneDrive).

## Prerequisites

- Windows 7 or later
- PowerShell 2.0+
- Read access on source, write access on target

## Files

| File | Purpose |
|------|---------|
| `FileSyncLauncher.vbs` | Control panel UI (start/stop/manage profiles) |
| `FileSync.ps1` | Background sync daemon |
| `Profiles\<name>\config.ini` | Per-profile settings (auto-generated) |

> Both `.vbs` and `.ps1` must be in the **same folder**.

## Installation

1. Place `FileSyncLauncher.vbs` and `FileSync.ps1` in the same folder.
2. Enable PowerShell scripts (one-time, run PowerShell as Admin):
   ```powershell
   Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
   ```

## Quick Start

1. Double-click `FileSyncLauncher.vbs`.
2. Enter `N` to create a new profile (e.g., name it `Work`).
3. Enter `1` to start the sync service.
4. First run only: enter source folder, target folder, notification preference.
5. Service starts in background and syncs immediately.

## Profiles (Multiple Simultaneous Syncs)

Each profile runs independently with its own config, PID, and log file. Use profiles to sync multiple folder pairs at the same time.

**To create a new profile:** In the profile selection screen, enter `N` and provide a name.

**To switch profiles:** Use option `6` in the main menu.

**To delete a profile:** Manually delete its folder from `Profiles\`.

**Profile naming rules:** Letters, numbers, hyphens, underscores only. Max 50 characters.

## Control Panel Menu

| Option | Action |
|--------|--------|
| 1 | Start sync service for current profile |
| 2 | Stop sync service for current profile |
| 3 | View log file for current profile |
| 4 | Change settings for current profile |
| 5 | View current status |
| 6 | Switch to a different profile |
| 0 | Exit control panel (services keep running) |

> Closing the control panel does **not** stop the sync. Use option `2` to stop.

## Configuration

File: `Profiles\<profile_name>\config.ini`

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

To reset a profile config: delete the profile's `config.ini` file (or the whole profile folder).

## Sync Behavior

| Event in Source | Action in Target |
|-----------------|------------------|
| File created | Copied |
| File modified (size or timestamp differs) | Overwritten |
| File deleted | Deleted |
| File renamed | Copied with new name |
| Subfolder created | Created on demand |
| Hidden files/folders (`.git`, `.env`) | Synced |

**Sync is one-way only** (source → target). Full recursive, no exclusions.

## Logs

**Location:** `%USERPROFILE%\FileSyncLogs\<profile_name>.log`

**Format:** `[YYYY-MM-DD HH:MM:SS] [LEVEL] Message`

**Levels:** `INFO`, `SUCCESS`, `WARN`, `ERROR`, `STARTUP`

**Sample:**
```
[2026-07-02 09:15:23] [INFO] File Sync Daemon STARTED (PID: 12345)
[2026-07-02 09:15:23] [INFO] Mode: FULL RECURSIVE (no exclusions)
[2026-07-02 09:15:26] [SUCCESS] SYNCED: src\app.js (Size: 12.45 KB)
[2026-07-02 09:18:45] [INFO] Event: Changed - src\app.js
[2026-07-02 09:20:23] [INFO] Heartbeat: daemon alive and watching
```

## File Structure

```
<app_folder>\
├── FileSyncLauncher.vbs
├── FileSync.ps1
└── Profiles\
    ├── Work\
    │   ├── config.ini
    │   ├── sync.pid     (present = running)
    │   └── sync.stop    (auto-managed stop signal)
    └── Personal\
        ├── config.ini
        ├── sync.pid
        └── sync.stop

%USERPROFILE%\FileSyncLogs\
├── Work.log
└── Personal.log
```

Do not manually edit `sync.pid` or `sync.stop`.

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

### Test 5: Hidden folder sync
1. Create a `.hidden` folder in source with a file inside.
2. **Expected:** Hidden folder and file appear in target.

### Test 6: Graceful stop
1. From control panel, select option `2`.
2. Confirm stop.
3. **Expected:** PID file removed, service status shows STOPPED.

### Test 7: Restart persistence
1. Stop service.
2. Restart control panel and select same profile.
3. **Expected:** Settings retained from previous session.

### Test 8: Invalid source
1. Change settings to non-existent source folder.
2. Try to start.
3. **Expected:** Error dialog "Source folder does not exist".

### Test 9: Network target
1. Configure target as UNC path.
2. Start service and modify a file.
3. **Expected:** File synced to network location.

### Test 10: Multiple profiles running
1. Create profile `A` with one folder pair, start it.
2. Open a second control panel instance.
3. Create profile `B` with a different folder pair, start it.
4. **Expected:** Both services run independently. Modifying files in each source syncs to respective targets. Separate logs generated.

### Test 11: Stop one profile without affecting the other
1. With profiles `A` and `B` both running, stop profile `A`.
2. **Expected:** Profile `A` stops, profile `B` continues syncing.

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
| Invalid profile name | Use only letters, numbers, hyphens, underscores |

### Log file not created
- Verify `%USERPROFILE%\FileSyncLogs\` folder is writable.
- Check `%TEMP%\FileSync_CRITICAL_ERROR.log` for fallback errors.

### Service won't stop gracefully
- Control panel option `2` will offer force-kill after 10 seconds.
- Manual kill: `taskkill /F /PID <PID>` (PID from `sync.pid`).

### Files not syncing
1. Check status (option 5) — must be RUNNING.
2. Check log for ERROR entries.
3. Verify write permissions on target.

### Wrong profile is showing
- Use option `6` to switch profiles.
- Verify profile folders exist under `Profiles\`.

## Performance

| Metric | Value (per profile) |
|--------|---------------------|
| CPU (idle) | ~0% |
| CPU (during sync) | Brief spike |
| RAM | 30-50 MB |
| Sync latency | 0.5-2 seconds |

Multiple profiles = multiple PowerShell processes. Each adds ~30-50 MB RAM.

## Known Limitations

- One-way sync only (no two-way/conflict resolution)
- No file exclusion filters (all files synced, including hidden)
- Not a Windows Service (runs as user process, stops on logoff)
- No sync queue for offline targets — failed syncs are logged but not retried
- NTFS permissions not preserved (target inherits parent folder ACL)

## Auto-Start on Login (Optional)

1. Press `Win + R`, type `shell:startup`, press Enter.
2. Create shortcut to `FileSyncLauncher.vbs` in that folder.

## Uninstall

1. Stop all running profiles (option 2 for each).
2. Delete app folder.
3. Delete `%USERPROFILE%\FileSyncLogs\` (optional).

## Support

**Author:** Abhishek Singh  
**Email:** standalone.abhishek@gmail.com  
**Team:** IT - Application Development