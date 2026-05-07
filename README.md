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
        ├──keybinds.ahk        //<- Entry point (run this as Admin)
        ├──WinHypr.ahk        //<- Backend API ~ DLL wrappers, smart logic, safety
        ├──VirtualDesktopAccessor.dll //<- COM bridge to Windows virtual desktop API
        ├── LICENSE
        ├──.gitignore   
        └──README.md
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

### Setup

1. Clone or download:
   ```
   https://github.com/OpalAayan/WinHypr-Switcher.git
   ```

2. Ensure `VirtualDesktopAccessor.dll` is in the same directory as the `.ahk` files.

3. **Run as Administrator:**
   ```
   Right-click keybinds.ahk -> Run as administrator
   Right-click WinHypr.ahk -> Run as administrator
   ```

> [!IMPORTANT]
> Windows blocks hotkeys from reaching windows that run at a higher privilege level than the AHK script. **Always run Win-Hypr as Administrator** if you use terminals, IDEs, or system tools launched with elevation.

### Run on Boot (Administrator)

Create a scheduled task in an elevated PowerShell:

```powershell
$A = New-ScheduledTaskAction -Execute "C:\Path\To\keybinds.ahk"
$T = New-ScheduledTaskTrigger -AtLogon
$P = New-ScheduledTaskPrincipal -GroupId "BUILTIN\Administrators" -RunLevel Highest
$S = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit 0
$D = New-ScheduledTask -Action $A -Principal $P -Trigger $T -Settings $S
Register-ScheduledTask WinHypr -InputObject $D
```
### Example Path~

```powershell
$A = New-ScheduledTaskAction -Execute "C:\Users\Admin\GitCrub\WinHypr-Switcher\keybinds.ahk"
$T = New-ScheduledTaskTrigger -AtLogon
$P = New-ScheduledTaskPrincipal -GroupId "BUILTIN\Administrators" -RunLevel Highest
$S = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit 0
$D = New-ScheduledTask -Action $A -Principal $P -Trigger $T -Settings $S
Register-ScheduledTask WinHypr -InputObject $D
```
> [!IMPORTANT]
> Do not run this using **Nushell** use *powershell -c ("Above commands")* but I will recommend using **POWERSHELL** _only_

---

## Troubleshooting

| Problem | Solution |
|---|---|
| Hotkeys don't work in elevated apps | Run `keybinds.ahk` as Administrator |
| `FATAL: Failed to load DLL` | Ensure `VirtualDesktopAccessor.dll` is in the script directory |
| `FATAL: Could not resolve DLL export` | Your DLL version may be incompatible with your Windows build. [Download the latest DLL](https://github.com/Ciantic/VirtualDesktopAccessor/releases) |
| Desktops overshoot (too many created) | Update to latest `WinHypr.ahk` — the deterministic loop fix resolves this |
| Explorer crashes on rapid switching | The spam lock should prevent this. If it persists, increase `DEBOUNCE_MS` in `WinHypr.ahk` |

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