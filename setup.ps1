# =============================================================================
# Win-Hypr Setup — One-Click Installer
# =============================================================================
# This script performs a full setup of Win-Hypr:
#   1. Verifies administrator privileges
#   2. Locates AutoHotkey v2 via PATH, common paths, and registry (universal)
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
    # -------------------------------------------------------------------------
    # Universal AHK Locator — strict fallback order:
    #   1. $env:PATH  (Get-Command)   — handles Scoop, Chocolatey, and standard installs
    #   2. Common hardcoded paths      — manual / MSI / portable installs
    #   3. Registry file association   — classic installer (wrapped in try/catch)
    # -------------------------------------------------------------------------

    # -- Step 1: Search $env:PATH via Get-Command -----------------------------
    # Try the most specific names first, then the generic shim name.
    $pathNames = @("AutoHotkey64.exe", "AutoHotkey.exe", "AutoHotkeyUX.exe")
    foreach ($name in $pathNames) {
        $cmd = Get-Command $name -ErrorAction SilentlyContinue
        if ($cmd -and (Test-Path $cmd.Source)) {
            return $cmd.Source
        }
    }

    # -- Step 2: Hardcoded common install locations ----------------------------
    $scoopBase = if ($env:SCOOP) { $env:SCOOP } else { Join-Path $env:USERPROFILE "scoop" }
    $commonPaths = @(
        # Standard v2 installer (MSI / setup.exe)
        "$env:ProgramFiles\AutoHotkey\v2\AutoHotkey64.exe",
        "$env:ProgramFiles\AutoHotkey\v2\AutoHotkey32.exe",
        "$env:ProgramFiles\AutoHotkey\v2\AutoHotkey.exe",
        # UX launcher (v2 multi-version install)
        "$env:ProgramFiles\AutoHotkey\UX\AutoHotkeyUX.exe",
        "$env:ProgramFiles\AutoHotkey\AutoHotkey64.exe",
        "$env:ProgramFiles\AutoHotkey\AutoHotkey.exe",
        # x86 fallback
        "${env:ProgramFiles(x86)}\AutoHotkey\AutoHotkey.exe",
        # Chocolatey
        "$env:ProgramData\chocolatey\bin\AutoHotkey.exe",
        "$env:ProgramData\chocolatey\lib\autohotkey\tools\AutoHotkey.exe",
        # Scoop (uses $env:SCOOP or default ~/scoop)
        (Join-Path $scoopBase "shims\AutoHotkey.exe"),
        (Join-Path $scoopBase "apps\autohotkey\current\v2\AutoHotkey64.exe"),
        (Join-Path $scoopBase "apps\autohotkey\current\v2\AutoHotkey.exe"),
        (Join-Path $scoopBase "apps\autohotkey\current\AutoHotkey.exe")
    )

    foreach ($p in $commonPaths) {
        if (Test-Path $p) { return $p }
    }

    # -- Step 3: Registry file association (legacy fallback) ------------------
    try {
        $regKeys = @(
            "HKLM:\SOFTWARE\Classes\AutoHotkeyScript\Shell\Open\Command",
            "HKCU:\SOFTWARE\Classes\AutoHotkeyScript\Shell\Open\Command",
            "HKLM:\SOFTWARE\Classes\.ahk\ShellNew\Command"
        )
        foreach ($key in $regKeys) {
            $regVal = (Get-ItemProperty $key -ErrorAction SilentlyContinue).'(default)'
            if ($regVal -and $regVal -match '^"?([^"]+\.exe)') {
                $resolved = $Matches[1]
                if (Test-Path $resolved) { return $resolved }
            }
        }
    } catch {
        # Registry keys absent or inaccessible -- fail silently.
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
