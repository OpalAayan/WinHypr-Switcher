# =============================================================================
# Win-Hypr Setup — One-Click Installer
# =============================================================================
# This script performs a full setup of Win-Hypr:
#   1. Verifies administrator privileges
#   2. Validates AutoHotkey v2 is installed and associated with .ahk files
#   3. Registers a scheduled task to run Win-Hypr at logon (elevated)
#   4. Launches the daemon immediately
#
# Usage:  Right-click → Run with PowerShell (as Administrator)
#     or: powershell -ExecutionPolicy Bypass -File .\setup.ps1
# =============================================================================

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# -- Constants ----------------------------------------------------------------
$TaskName     = "WinHypr"
$ScriptDir    = $PSScriptRoot
$EntryPoint   = Join-Path $ScriptDir "keybinds.ahk"
$DllPath      = Join-Path $ScriptDir "VirtualDesktopAccessor.dll"

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

function Find-AutoHotkey {
    # Try to resolve the .ahk file association first (most reliable)
    $ahkExe = (Get-ItemProperty "HKLM:\SOFTWARE\Classes\AutoHotkeyScript\Shell\Open\Command" -ErrorAction SilentlyContinue).'(default)'
    if ($ahkExe) {
        # Extract the executable path from something like: "C:\...\AutoHotkey64.exe" "%1" %*
        if ($ahkExe -match '^"?([^"]+\.exe)') {
            $resolved = $Matches[1]
            if (Test-Path $resolved) { return $resolved }
        }
    }

    # Fallback: search PATH
    $inPath = Get-Command "AutoHotkey*.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($inPath) { return $inPath.Source }

    # Fallback: common install locations
    $commonPaths = @(
        "$env:ProgramFiles\AutoHotkey\v2\AutoHotkey64.exe",
        "$env:ProgramFiles\AutoHotkey\v2\AutoHotkey32.exe",
        "$env:ProgramFiles\AutoHotkey\AutoHotkey64.exe",
        "$env:ProgramFiles\AutoHotkey\AutoHotkey.exe",
        "${env:ProgramFiles(x86)}\AutoHotkey\AutoHotkey.exe"
    )
    foreach ($p in $commonPaths) {
        if (Test-Path $p) { return $p }
    }

    return $null
}

# =============================================================================
# PREFLIGHT CHECKS
# =============================================================================

Write-Host ""
Write-Host "========================================" -ForegroundColor Magenta
Write-Host "       Win-Hypr Setup Wizard" -ForegroundColor Magenta
Write-Host "========================================" -ForegroundColor Magenta
Write-Host ""

# 1. Admin check
Write-Step "Checking administrator privileges..."
if (-not (Test-Administrator)) {
    Write-Fail "This script must be run as Administrator."
    Write-Fail "Right-click PowerShell → 'Run as Administrator', then re-run this script."
    Write-Host ""
    Write-Host "Press any key to exit..." -ForegroundColor DarkGray
    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    exit 1
}
Write-Ok "Running as Administrator."

# 2. Validate required files exist
Write-Step "Validating project files..."

if (-not (Test-Path $EntryPoint)) {
    Write-Fail "keybinds.ahk not found at: $EntryPoint"
    Write-Fail "Make sure you are running setup.ps1 from within the WinHypr-Switcher directory."
    Write-Host ""
    Write-Host "Press any key to exit..." -ForegroundColor DarkGray
    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    exit 1
}

if (-not (Test-Path $DllPath)) {
    Write-Fail "VirtualDesktopAccessor.dll not found at: $DllPath"
    Write-Fail "Download it from: https://github.com/Ciantic/VirtualDesktopAccessor/releases"
    Write-Host ""
    Write-Host "Press any key to exit..." -ForegroundColor DarkGray
    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    exit 1
}

Write-Ok "All project files present."

# 3. AutoHotkey detection
Write-Step "Locating AutoHotkey installation..."
$ahkPath = Find-AutoHotkey

if (-not $ahkPath) {
    Write-Fail "AutoHotkey v2 is not installed or not found."
    Write-Fail "Download it from: https://www.autohotkey.com/"
    Write-Host ""
    Write-Host "Press any key to exit..." -ForegroundColor DarkGray
    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    exit 1
}

Write-Ok "Found AutoHotkey at: $ahkPath"

# =============================================================================
# SETUP
# =============================================================================

# 4. Remove existing scheduled task (idempotent re-setup)
Write-Step "Checking for existing scheduled task..."
$existingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($existingTask) {
    Write-Warn "Existing '$TaskName' task found — removing it for a clean setup."
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    Write-Ok "Old task removed."
} else {
    Write-Ok "No existing task — clean install."
}

# 5. Register scheduled task
Write-Step "Registering scheduled task '$TaskName'..."

$Action   = New-ScheduledTaskAction -Execute $ahkPath -Argument "`"$EntryPoint`"" -WorkingDirectory $ScriptDir
$Trigger  = New-ScheduledTaskTrigger -AtLogon
$Principal = New-ScheduledTaskPrincipal -GroupId "BUILTIN\Administrators" -RunLevel Highest
$Settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -ExecutionTimeLimit (New-TimeSpan -Seconds 0) `
    -RestartCount 3 `
    -RestartInterval (New-TimeSpan -Minutes 1)

$Task = New-ScheduledTask -Action $Action -Principal $Principal -Trigger $Trigger -Settings $Settings
Register-ScheduledTask -TaskName $TaskName -InputObject $Task | Out-Null

Write-Ok "Scheduled task '$TaskName' registered successfully."
Write-Ok "  Entry point : $EntryPoint"
Write-Ok "  AHK engine  : $ahkPath"
Write-Ok "  Trigger     : At logon (elevated)"

# 6. Kill any already-running instances before starting fresh
Write-Step "Stopping any existing Win-Hypr instances..."
Get-Process -Name "AutoHotkey*" -ErrorAction SilentlyContinue | Where-Object {
    try {
        $_.MainModule.FileName -eq $ahkPath -or
        $_.CommandLine -like "*keybinds.ahk*" -or
        $_.CommandLine -like "*WinHypr*"
    } catch { $false }
} | Stop-Process -Force -ErrorAction SilentlyContinue

# Also do a broad kill in case WMI fails (AHK processes are cheap to restart)
# Only kill processes whose path matches our AHK executable
Start-Sleep -Milliseconds 500

# 7. Launch the daemon now
Write-Step "Launching Win-Hypr daemon..."
Start-Process -FilePath $ahkPath -ArgumentList "`"$EntryPoint`"" -WorkingDirectory $ScriptDir -Verb RunAs
Start-Sleep -Seconds 1

# Verify it's running
$running = Get-Process -Name "AutoHotkey*" -ErrorAction SilentlyContinue
if ($running) {
    Write-Ok "Win-Hypr daemon is running! (PID: $($running[0].Id))"
} else {
    Write-Warn "Daemon may not have started. Check for AHK error dialogs."
}

# =============================================================================
# DONE
# =============================================================================

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "       Setup Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Win-Hypr is now active and will start automatically at logon." -ForegroundColor White
Write-Host "  Try pressing  Super + 1  through  Super + 9  to switch desktops." -ForegroundColor DarkGray
Write-Host ""
Write-Host "  To uninstall:  .\uninstall.ps1" -ForegroundColor DarkGray
Write-Host ""
Write-Host "Press any key to exit..." -ForegroundColor DarkGray
$null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
