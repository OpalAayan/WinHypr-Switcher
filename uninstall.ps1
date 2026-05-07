# =============================================================================
# Win-Hypr Uninstaller
# =============================================================================
# This script cleanly disables Win-Hypr:
#   1. Verifies administrator privileges
#   2. Unregisters the scheduled task (stops auto-start at logon)
#   3. Terminates all running Win-Hypr / AutoHotkey processes
#   4. Verifies everything is cleaned up
#
# The project files are left in place (dormant). To fully remove Win-Hypr,
# delete the WinHypr-Switcher folder after running this script.
#
# Usage:  Right-click -> Run with PowerShell (as Administrator)
#     or: powershell -ExecutionPolicy Bypass -File .\uninstall.ps1
# =============================================================================

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# -- Constants ----------------------------------------------------------------
$TaskName = "WinHypr"

# -- Helpers ------------------------------------------------------------------

function Write-Step  { param([string]$msg) Write-Host "[*] $msg" -ForegroundColor Cyan }
function Write-Ok    { param([string]$msg) Write-Host "[+] $msg" -ForegroundColor Green }
function Write-Warn  { param([string]$msg) Write-Host "[!] $msg" -ForegroundColor Yellow }
function Write-Fail  { param([string]$msg) Write-Host "[-] $msg" -ForegroundColor Red }

function Test-Administrator {
    $identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# =============================================================================
# PREFLIGHT
# =============================================================================

Write-Host ""
Write-Host "========================================" -ForegroundColor Red
Write-Host "       Win-Hypr Uninstaller" -ForegroundColor Red
Write-Host "========================================" -ForegroundColor Red
Write-Host ""

# 1. Admin check
Write-Step "Checking administrator privileges..."
if (-not (Test-Administrator)) {
    Write-Fail "This script must be run as Administrator."
    Write-Fail "Right-click PowerShell -> Run as Administrator, then re-run this script."
    Write-Host ""
    Write-Host "Press any key to exit..." -ForegroundColor DarkGray
    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    exit 1
}
Write-Ok "Running as Administrator."

# =============================================================================
# UNINSTALL
# =============================================================================

$errors = 0

# 2. Remove scheduled task
Write-Step "Removing scheduled task '$TaskName'..."
$task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($task) {
    try {
        # Stop the task if it is currently running
        Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-Ok "Scheduled task '$TaskName' removed."
    } catch {
        Write-Fail "Failed to remove scheduled task: $_"
        $errors++
    }
} else {
    Write-Warn "No scheduled task '$TaskName' found -- skipping."
}

# 3. Terminate AutoHotkey processes running Win-Hypr scripts
Write-Step "Terminating Win-Hypr processes..."

$ahkProcesses = @(Get-Process -Name "AutoHotkey*" -ErrorAction SilentlyContinue)

if ($ahkProcesses.Count -gt 0) {
    $killed = 0
    $scriptRoot = $PSScriptRoot

    foreach ($proc in $ahkProcesses) {
        try {
            # Identify if this AHK instance is ours by checking command line via WMI
            $wmiProc = Get-CimInstance Win32_Process -Filter "ProcessId = $($proc.Id)" -ErrorAction SilentlyContinue
            $cmdLine = ""
            if ($wmiProc) { $cmdLine = $wmiProc.CommandLine }

            $isWinHypr = $false
            if ($cmdLine -like "*keybinds.ahk*") { $isWinHypr = $true }
            if ($cmdLine -like "*WinHypr*") { $isWinHypr = $true }
            if ($cmdLine -like "*$scriptRoot*") { $isWinHypr = $true }

            if ($isWinHypr) {
                Stop-Process -Id $proc.Id -Force -ErrorAction Stop
                Write-Ok "  Killed Win-Hypr process (PID: $($proc.Id))"
                $killed++
            } else {
                Write-Warn "  Skipped non-Win-Hypr AHK process (PID: $($proc.Id))"
            }
        } catch {
            Write-Warn "  Could not inspect PID $($proc.Id) -- will attempt force kill."
        }
    }

    # If we could not identify any specific processes (WMI failed), ask the user
    if ($killed -eq 0) {
        Write-Warn "Could not identify Win-Hypr processes specifically."
        Write-Host ""
        $response = Read-Host "  Kill ALL AutoHotkey processes? (y/N)"
        if ($response -eq 'y' -or $response -eq 'Y') {
            Stop-Process -Name "AutoHotkey*" -Force -ErrorAction SilentlyContinue
            Write-Ok "All AutoHotkey processes terminated."
        } else {
            Write-Warn "Skipped -- some AHK processes may still be running."
        }
    }
} else {
    Write-Ok "No AutoHotkey processes running."
}

# 4. Wait for handles to release
Write-Step "Waiting for process handles to release..."
Start-Sleep -Seconds 1

# =============================================================================
# VERIFICATION
# =============================================================================

Write-Step "Verifying cleanup..."

$verifyOk = $true

# Check task is gone
$taskCheck = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($taskCheck) {
    Write-Fail "  Scheduled task '$TaskName' still exists!"
    $verifyOk = $false
} else {
    Write-Ok "  Scheduled task removed."
}

# Check no WinHypr AHK processes remain
$remainingAhk = Get-Process -Name "AutoHotkey*" -ErrorAction SilentlyContinue
if ($remainingAhk) {
    $ours = $false
    $scriptRoot = $PSScriptRoot
    foreach ($proc in $remainingAhk) {
        $wmiProc = Get-CimInstance Win32_Process -Filter "ProcessId = $($proc.Id)" -ErrorAction SilentlyContinue
        if ($wmiProc) {
            $cl = $wmiProc.CommandLine
            if ($cl -like "*keybinds.ahk*" -or $cl -like "*WinHypr*" -or $cl -like "*$scriptRoot*") {
                $ours = $true
                break
            }
        }
    }
    if ($ours) {
        Write-Fail "  Win-Hypr processes still running!"
        $verifyOk = $false
    } else {
        Write-Ok "  No Win-Hypr processes running (other AHK instances left alone)."
    }
} else {
    Write-Ok "  No AutoHotkey processes running."
}

# =============================================================================
# RESULT
# =============================================================================

Write-Host ""

if ($verifyOk -and $errors -eq 0) {
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "    Win-Hypr Uninstalled Successfully" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Win-Hypr is fully disabled. Keybinds are back to Windows defaults." -ForegroundColor White
    Write-Host "  The project files remain in: $PSScriptRoot" -ForegroundColor DarkGray
    Write-Host "  To fully remove, delete that folder manually." -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  To re-enable:  .\setup.ps1" -ForegroundColor DarkGray
} else {
    Write-Host "========================================" -ForegroundColor Yellow
    Write-Host "    Uninstall completed with warnings" -ForegroundColor Yellow
    Write-Host "========================================" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Some steps may have had issues. Review the output above." -ForegroundColor White
    Write-Host "  You may need to manually kill AutoHotkey from Task Manager." -ForegroundColor DarkGray
}

Write-Host ""
Write-Host "Press any key to exit..." -ForegroundColor DarkGray
$null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')