<p align="center">
  <img src="https://img.shields.io/badge/Windows_11-0078D4?style=for-the-badge&logo=windows11&logoColor=white" alt="Windows 11">
  <img src="https://img.shields.io/badge/AutoHotkey_v2-334455?style=for-the-badge&logo=autohotkey&logoColor=white" alt="AHK v2">
  <img src="https://img.shields.io/badge/License-MIT-green?style=for-the-badge" alt="MIT License">
</p>

<h1 align="center">Win-Hypr</h1>

<p align="center">
  <strong>Hyprland-style virtual desktop management for Windows 11.</strong><br>
  Zero GUI. Pure keyboard. Instant switching.
</p>

 > This is a fork of
  [pmb6tz/windows-desktop-switcher](https://github.com/pmb6tz/windows-desktop-switcher) 


## What is Win-Hypr?

Win-Hypr brings the workflow philosophy of [Hyprland](https://hyprland.org/) ~ the beloved Wayland compositor for Linux -- to Windows 11.

Instead of clicking through the clunky Task View, you get **instant, numbered workspace switching** with a single keystroke. Desktops are created **dynamically on demand** -- press <kbd>Super</kbd>+<kbd>7</kbd> and desktops 1 through 7 will exist, instantly.

Built on [AutoHotkey v2](https://www.autohotkey.com/) and powered by [VirtualDesktopAccessor.dll](https://github.com/Ciantic/VirtualDesktopAccessor), Win-Hypr is lightweight, hackable, and fast.

---

## Features

| Feature | Description |
|---|---|
| **Instant Switch** | Jump directly to any desktop 1-9 with <kbd>Super</kbd>+<kbd>N</kbd> |
| **Dynamic Creation** | Desktops are created automatically if they don't exist yet |
| **Window Teleport** | Move the focused window to any desktop with <kbd>Super</kbd>+<kbd>Shift</kbd>+<kbd>N</kbd> |
| **Focus Retention** | Moved windows stay focused -- no lost activation |
| **Spam Protection** | Built-in transition lock prevents Explorer crashes from rapid inputs |
| **Deterministic Creation** | Pre-calculates exact desktop deficit ~ no overshoot, no race conditions |
| **Zero GUI** | No tray menus, no popups, no settings windows ~ just keys |

---

## Keybinds

All keybinds are defined in [`keybinds.ahk`](keybinds.ahk) and can be freely customized.

### Workspace Navigation

| Keys | Action |
|---|---|
| <kbd>Super</kbd> + <kbd>1</kbd> – <kbd>9</kbd> | Switch to desktop 1–9 (auto-creates if needed) |
| <kbd>Super</kbd> + <kbd>Ctrl</kbd> + <kbd>←</kbd> / <kbd>→</kbd> | Cycle desktops left / right |

### Window Management

| Keys | Action |
|---|---|
| <kbd>Super</kbd> + <kbd>Shift</kbd> + <kbd>1</kbd> – <kbd>9</kbd> | Move active window to desktop 1–9 and follow it |
| <kbd>Super</kbd> + <kbd>Q</kbd> | Close active window |
| <kbd>Super</kbd> + <kbd>V</kbd> | Toggle maximize / restore |

### App Launchers

| Keys | Action |
|---|---|
| <kbd>Ctrl</kbd> + <kbd>Alt</kbd> + <kbd>T</kbd> | Open Windows Terminal |

---

## Architecture

```
WinHypr-Switcher/
        ├── keybinds.ahk                 ← Entry point (run this as Admin)
        ├── WinHypr.ahk                  ← Backend API ~ DLL wrappers, smart logic, safety
        ├── VirtualDesktopAccessor.dll   ← COM bridge to Windows virtual desktop API
        ├── setup.ps1                    ← One-click installer (registers task + starts daemon)
        ├── uninstall.ps1                ← Clean uninstaller (kills daemon + removes task)
        ├── nuke.ps1                     ← Ruthless directory deletion (force-closes file locks)
        ├── LICENSE
        ├── .gitignore
        └── README.md
```

### How It Works

```
User presses Super+7
        │
        ▼
keybinds.ahk -> SwitchToDesktop(7)
                        │
                        ├─ isSwitching lock acquired
                        ├─ GetDesktopCount() → 3
                        ├─ Deficit: 7 - 3 = 4
                        ├─ Loop 4 { CreateDesktop() }     ← deterministic, no re-query
                        ├─ GoToDesktopNumber(7)            ← DLL call (1→0 index)
                        ├─ _FocusForemostWindow()
                        └─ isSwitching lock released
```

### The 0-Index Rule

Windows' virtual desktop API is **0-indexed** (Desktop 1 = index 0). Win-Hypr's API functions accept **1-indexed** numbers and translate internally -- you never think about zero-indexing.

### Dynamic Workspace Creation

When you switch to desktop `N` and only `M` desktops exist (`N > M`), Win-Hypr calculates `needed = N - M` once, then fires `CreateDesktop()` exactly `needed` times in a deterministic loop. It **does not** re-query `GetDesktopCount()` inside the loop -- this eliminates the race condition where the OS animation lags behind the DLL, causing overshoot.

### Spam Protection

A global `isSwitching` lock (with `try/finally` guarantee) prevents concurrent transitions. If a hotkey fires while a switch is already in progress, the input is silently dropped. This prevents Explorer crashes from interrupted desktop animations.

---

## Installation

### Prerequisites

- **Windows 11** (22H2 or later recommended)
- **[AutoHotkey v2.0+](https://www.autohotkey.com/)** -- do **not** install v1
- **[Sysinternals Handle](https://learn.microsoft.com/en-us/sysinternals/downloads/handle)** *(optional, for full removal)* -- install via `winget install SysInternals.Handle`

### Quick Setup (Recommended)

1. Clone or download:
   ```
   git clone https://github.com/OpalAayan/WinHypr-Switcher.git
   ```

2. Open **PowerShell as Administrator** and run:
   ```powershell
   cd path\to\WinHypr-Switcher
   powershell -ExecutionPolicy Bypass -File .\setup.ps1
   ```

That's it. The setup script will:
- ✅ Verify AutoHotkey v2 is installed
- ✅ Validate all required files (`keybinds.ahk`, `VirtualDesktopAccessor.dll`)
- ✅ Register a scheduled task to start Win-Hypr at logon (elevated)
- ✅ Launch the daemon immediately

> [!IMPORTANT]
> Windows blocks hotkeys from reaching windows that run at a higher privilege level than the AHK script. **Always run Win-Hypr as Administrator** — the setup script handles this automatically via the scheduled task.

### Uninstall

Uninstalling is a **two-step process**: first *disable* Win-Hypr, then *delete* the folder.

#### Step 1 — Disable (soft uninstall)

Run the uninstall script to stop the daemon and remove the scheduled task:

```powershell
powershell -ExecutionPolicy Bypass -File .\uninstall.ps1
```

This will:
-  Terminate the Win-Hypr daemon
-  Remove the `WinHypr` scheduled task (no more auto-start)
-  Verify everything is cleaned up

Project files are left in place (dormant). To re-enable later, just run `setup.ps1` again.

#### Step 2 — Nuke (full removal)

Win-Hypr injects `VirtualDesktopAccessor.dll` into the system, which causes Windows to hold file locks (`OS Error 32: File in Use`) on the project directory. Explorer, terminal sessions, and IDE file-watchers can all prevent deletion.

**`nuke.ps1`** handles this automatically. It will:

1. **Auto-discover** the WinHypr-Switcher directory (via scheduled task, script location, or common paths)
2. **Unregister** the `WinHypr` scheduled task
3. **Kill** all AutoHotkey processes
4. **Detect** IDE file-watchers (VS Code, VSCodium) and prompt to close them
5. **Redirect** any Explorer windows browsing the target directory
6. **Force-close** all open file handles using Sysinternals `handle.exe`
7. **Delete** the directory (retry loop with handle re-scanning between attempts)

```powershell
# Auto-discovers and nukes the directory:
powershell -ExecutionPolicy Bypass -File .\nuke.ps1

# Or specify the path explicitly:
powershell -ExecutionPolicy Bypass -File .\nuke.ps1 -TargetPath "C:\path\to\WinHypr-Switcher"

# Also force-kill VS Code / VSCodium:
powershell -ExecutionPolicy Bypass -File .\nuke.ps1 -ForceKillApps
```

> [!NOTE]
> `nuke.ps1` is **self-relocating** -- if you run it from inside the target directory, it will automatically copy itself to `%TEMP%` and relaunch. It also auto-escapes if your terminal is `cd`'d into the target. No manual steps required.

> [!TIP]
> For best results, install Sysinternals Handle beforehand:
> ```powershell
> winget install SysInternals.Handle
> ```
> Without `handle.exe`, the script can still kill processes and retry deletion, but cannot force-close individual file handles.

### Manual Setup (Advanced)

If you prefer to set things up manually:

1. Ensure `VirtualDesktopAccessor.dll` is in the same directory as the `.ahk` files.

2. **Run as Administrator:**
   ```
   Right-click keybinds.ahk → Run as administrator
   ```

3. **Run on Boot** — Create a scheduled task in an elevated PowerShell:

   ```powershell
   $A = New-ScheduledTaskAction -Execute "C:\Path\To\AutoHotkey64.exe" -Argument '"C:\Path\To\keybinds.ahk"'
   $T = New-ScheduledTaskTrigger -AtLogon
   $P = New-ScheduledTaskPrincipal -GroupId "BUILTIN\Administrators" -RunLevel Highest
   $S = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit 0
   $D = New-ScheduledTask -Action $A -Principal $P -Trigger $T -Settings $S
   Register-ScheduledTask WinHypr -InputObject $D
   ```

> [!IMPORTANT]
> Do not run setup/uninstall/nuke scripts using **Nushell** — use `powershell -c "commands"` or run from a native **PowerShell** session.

---

## Troubleshooting

| Problem | Solution |
|---|---|
| Hotkeys don't work in elevated apps | Run `keybinds.ahk` as Administrator |
| `FATAL: Failed to load DLL` | Ensure `VirtualDesktopAccessor.dll` is in the script directory |
| `FATAL: Could not resolve DLL export` | Your DLL version may be incompatible with your Windows build. [Download the latest DLL](https://github.com/Ciantic/VirtualDesktopAccessor/releases) |
| Desktops overshoot (too many created) | Update to latest `WinHypr.ahk` — the deterministic loop fix resolves this |
| Explorer crashes on rapid switching | The spam lock should prevent this. If it persists, increase `DEBOUNCE_MS` in `WinHypr.ahk` |
| **Can't delete the folder** (OS Error 32) | Run `nuke.ps1` — it force-closes all file locks and deletes the directory. See [Nuke (full removal)](#step-2--nuke-full-removal) above |
| `nuke.ps1` fails even after closing handles | Some locks are held by protected system processes. **Reboot** and run `nuke.ps1` immediately before opening anything |

---

## Debugging

Win-Hypr emits `OutputDebug` messages at every stage. To view them:

1. Download [DebugView](https://learn.microsoft.com/en-us/sysinternals/downloads/debugview) from SysInternals
2. Run DebugView **as Administrator**
3. Filter for `[Win-Hypr]`

```
[Win-Hypr v1.0.0] DLL loaded (handle: 0x7FF...)
[Win-Hypr] Resolved: GetDesktopCount -> 0x7FF...
[Win-Hypr v1.0.0] Desktops: 3 | Current: 1 | Ready
[Win-Hypr] SwitchToDesktop: Creating 4 desktop(s) (3 → 7)
[Win-Hypr] SwitchToDesktop: Switching 1 → 7
```

---

## Customization

Edit [`keybinds.ahk`](keybinds.ahk) to change any binding. The modifier syntax is:

| Symbol | Key |
|---|---|
| `#` | <kbd>Super</kbd> (Win) |
| `+` | <kbd>Shift</kbd> |
| `^` | <kbd>Ctrl</kbd> |
| `!` | <kbd>Alt</kbd> |

Example — remap desktop switching to <kbd>Ctrl</kbd>+<kbd>Alt</kbd>+<kbd>1-9</kbd>:
```ahk
^!1::SwitchToDesktop(1)
^!2::SwitchToDesktop(2)
; ... etc
```

See the [AutoHotkey v2 Hotkeys docs](https://www.autohotkey.com/docs/v2/Hotkeys.htm) for full syntax.

---

## Credits

- [Ciantic/VirtualDesktopAccessor](https://github.com/Ciantic/VirtualDesktopAccessor) -- the DLL that makes programmatic desktop control possible
- [pmb6tz/windows-desktop-switcher](https://github.com/pmb6tz/windows-desktop-switcher) -- the original AHK v1 project that inspired this rewrite
- [Hyprland](https://hyprland.org/) -- Wayland window manager Thanks vaxry :3

---

## License

MIT ~ see [LICENSE.txt](LICENSE.txt).
>*Just give credit* ~~feel free to steal~~