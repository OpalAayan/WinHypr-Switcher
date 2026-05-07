<#
.SYNOPSIS
    Ruthless directory deletion for WinHypr-Switcher.

.DESCRIPTION
    When Windows throws OS Error 32 (File in Use) and refuses to delete the
    WinHypr-Switcher folder, this script hunts down every locking process
    and obliterates the directory.

    If no -TargetPath is given the script auto-discovers it by checking:
      1. The WinHypr scheduled-task action path
      2. $PSScriptRoot  (when the script lives inside a WinHypr-Switcher dir)
      3. Common user-profile locations

    If the script itself lives inside the target it will automatically copy
    itself to %TEMP% and relaunch from there -- no manual intervention needed.

.PARAMETER TargetPath
    Absolute path to the directory to delete.
    Optional -- the script will auto-discover it if omitted.

.PARAMETER ForceKillApps
    Kill IDE/editor processes without prompting.

.EXAMPLE
    .\nuke.ps1
    # Auto-discovers and nukes the WinHypr-Switcher directory.

.EXAMPLE
    .\nuke.ps1 -TargetPath "C:\Users\Me\WinHypr-Switcher"

.EXAMPLE
    .\nuke.ps1 -ForceKillApps
#>

param(
    [Parameter(Position = 0)]
    [string]$TargetPath,

    [switch]$ForceKillApps,

    # Internal flag -- signals the script was relaunched from %TEMP%.
    [switch]$_Relocated
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# -- Constants ----------------------------------------------------------------
$TaskName       = "WinHypr"
$MaxRetries     = 5
$RetryDelaySec  = 2
$IDEProcesses   = @("Code", "VSCodium")
$FolderName     = "WinHypr-Switcher"

# -- Helpers ------------------------------------------------------------------

function Write-Step   { param([string]$msg) Write-Host "[*] $msg" -ForegroundColor Cyan }
function Write-Ok     { param([string]$msg) Write-Host "[+] $msg" -ForegroundColor Green }
function Write-Warn   { param([string]$msg) Write-Host "[!] $msg" -ForegroundColor Yellow }
function Write-Fail   { param([string]$msg) Write-Host "[-] $msg" -ForegroundColor Red }
function Write-Detail { param([string]$msg) Write-Host "    $msg" -ForegroundColor DarkGray }

function Test-Administrator {
    $identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-NormalizedPath([string]$p) {
    return $p.TrimEnd('\').ToLowerInvariant()
}

function Find-HandleExe {
    $h = Get-Command "handle64.exe" -ErrorAction SilentlyContinue
    if ($h) { return $h.Source }
    $h = Get-Command "handle.exe" -ErrorAction SilentlyContinue
    if ($h) { return $h.Source }
    return $null
}

function Get-LockingHandles([string]$HandleExePath, [string]$DirPath) {
    $results = @()
    try {
        $raw = & $HandleExePath -accepteula -nobanner $DirPath 2>&1
        foreach ($line in $raw) {
            if ($line -isnot [string]) { continue }
            $text = $line.Trim()
            if ($text.Length -eq 0) { continue }
            if ($text -match '^Nthandle|^Copyright|^Sysinternals|^Handle v|^No matching') { continue }
            if ($text -match '^(\S+)\s+pid:\s*(\d+)\s+type:\s*(\S+)\s+([0-9A-Fa-f]+):') {
                $results += [PSCustomObject]@{
                    Process   = $Matches[1]
                    PID       = [int]$Matches[2]
                    Type      = $Matches[3]
                    HandleHex = $Matches[4]
                    Line      = $text
                }
            }
        }
    } catch {
        Write-Detail "handle.exe query failed: $_"
    }
    return ,$results
}

function Close-Handle([string]$HandleExePath, [int]$ProcessId, [string]$HandleHex) {
    try {
        & $HandleExePath -accepteula -nobanner -c $HandleHex -p $ProcessId -y 2>&1 | Out-Null
        return $true
    } catch {
        return $false
    }
}

function Close-AllLockingHandles([string]$HandleExePath, [string]$DirPath) {
    $handles = Get-LockingHandles $HandleExePath $DirPath
    $closed = 0
    foreach ($h in $handles) {
        $desc = $h.Process + " (PID:" + $h.PID + " Handle:0x" + $h.HandleHex + ")"
        $ok = Close-Handle $HandleExePath $h.PID $h.HandleHex
        if ($ok) {
            Write-Ok "  Closed: $desc"
            $closed++
        } else {
            Write-Warn "  Failed: $desc"
        }
    }
    return $closed
}

# Try to discover the WinHypr-Switcher directory automatically.
function Find-WinHyprDirectory {
    # Strategy 1: Scheduled task action path
    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($task) {
        $actions = @($task.Actions)
        foreach ($a in $actions) {
            if ($a.WorkingDirectory -and (Test-Path $a.WorkingDirectory -PathType Container)) {
                return $a.WorkingDirectory
            }
            # Fall back to parsing the script path from the action
            $argStr = $a.Arguments
            if ($argStr) {
                $cleaned = $argStr -replace '"', ''
                $scriptDir = Split-Path $cleaned -Parent -ErrorAction SilentlyContinue
                if ($scriptDir -and (Test-Path $scriptDir -PathType Container)) {
                    return $scriptDir
                }
            }
        }
    }

    # Strategy 2: $PSScriptRoot contains the folder name
    if ($PSScriptRoot) {
        $leaf = Split-Path $PSScriptRoot -Leaf
        if ($leaf -eq $FolderName) {
            return $PSScriptRoot
        }
        # Maybe the script is one level up
        $candidate = Join-Path $PSScriptRoot $FolderName
        if (Test-Path $candidate -PathType Container) {
            return $candidate
        }
    }

    # Strategy 3: Common profile locations
    $candidates = @(
        (Join-Path $env:USERPROFILE $FolderName),
        (Join-Path $env:USERPROFILE ("Desktop\" + $FolderName)),
        (Join-Path $env:USERPROFILE ("Downloads\" + $FolderName)),
        (Join-Path $env:USERPROFILE ("Documents\" + $FolderName)),
        (Join-Path $env:USERPROFILE ("GitCrub\" + $FolderName))
    )
    foreach ($c in $candidates) {
        if (Test-Path $c -PathType Container) {
            return $c
        }
    }

    # Strategy 4: Current directory or parent
    $pwd = (Get-Location).Path
    if ((Split-Path $pwd -Leaf) -eq $FolderName) {
        return $pwd
    }
    $candidate = Join-Path $pwd $FolderName
    if (Test-Path $candidate -PathType Container) {
        return $candidate
    }

    return $null
}

# =============================================================================
# BANNER
# =============================================================================

Write-Host ""
Write-Host "  _   _ _   _ _  ______" -ForegroundColor Red
Write-Host " | \ | | | | | |/ / ___|" -ForegroundColor Red
Write-Host " |  \| | | | |   /|  _|" -ForegroundColor Red
Write-Host " | |\  | |_| | . \| |___" -ForegroundColor Yellow
Write-Host " |_| \_|\___/|_|\_\_____|" -ForegroundColor Yellow
Write-Host ""
Write-Host "  Ruthless Directory Deletion for WinHypr" -ForegroundColor DarkGray
Write-Host ""
Write-Host ("=" * 60) -ForegroundColor DarkRed

# =============================================================================
# PREFLIGHT -- Admin Elevation
# =============================================================================

Write-Step "Checking administrator privileges..."
if (-not (Test-Administrator)) {
    Write-Warn "Not running as Administrator -- attempting elevation..."
    try {
        $argList = @("-ExecutionPolicy", "Bypass", "-File", ('"' + $PSCommandPath + '"'))
        if ($TargetPath)    { $argList += @("-TargetPath", ('"' + $TargetPath + '"')) }
        if ($ForceKillApps) { $argList += "-ForceKillApps" }
        if ($_Relocated)    { $argList += "-_Relocated" }

        Start-Process -FilePath "powershell.exe" -ArgumentList $argList -Verb RunAs
        Write-Ok "Elevated process launched. This window will close."
        exit 0
    } catch {
        Write-Fail "Failed to elevate. Right-click PowerShell -> Run as Administrator."
        Write-Host ""
        Write-Host "Press any key to exit..." -ForegroundColor DarkGray
        $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
        exit 1
    }
}
Write-Ok "Running as Administrator."

# =============================================================================
# PREFLIGHT -- Resolve Target Path
# =============================================================================

Write-Step "Resolving target directory..."

if (-not $TargetPath) {
    $TargetPath = Find-WinHyprDirectory
    if ($TargetPath) {
        Write-Ok "Auto-discovered: $TargetPath"
    } else {
        Write-Fail "Could not auto-discover the $FolderName directory."
        Write-Detail "Pass it explicitly:  .\nuke.ps1 -TargetPath <path>"
        Write-Host ""
        Write-Host "Press any key to exit..." -ForegroundColor DarkGray
        $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
        exit 1
    }
}

$TargetPath = [System.IO.Path]::GetFullPath($TargetPath)

if (-not (Test-Path $TargetPath -PathType Container)) {
    Write-Fail "Target does not exist: $TargetPath"
    Write-Detail "Nothing to nuke."
    Write-Host ""
    Write-Host "Press any key to exit..." -ForegroundColor DarkGray
    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    exit 1
}
Write-Ok "Target: $TargetPath"

$normalizedTarget = Get-NormalizedPath $TargetPath

# =============================================================================
# PREFLIGHT -- Self-Relocation (script inside target)
# =============================================================================

if ($PSScriptRoot -and (Get-NormalizedPath $PSScriptRoot).StartsWith($normalizedTarget)) {
    if ($_Relocated) {
        # We already relocated once and we are STILL inside? Something is wrong.
        Write-Fail "Self-relocation loop detected. Aborting."
        Write-Host "Press any key to exit..." -ForegroundColor DarkGray
        $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
        exit 1
    }

    Write-Warn "Script is inside the target directory -- self-relocating to %TEMP%..."
    $tempCopy = Join-Path $env:TEMP "nuke_winhypr.ps1"
    Copy-Item -Path $PSCommandPath -Destination $tempCopy -Force
    Write-Ok "Copied to: $tempCopy"

    $argList = @(
        "-ExecutionPolicy", "Bypass",
        "-File", ('"' + $tempCopy + '"'),
        "-TargetPath", ('"' + $TargetPath + '"'),
        "-_Relocated"
    )
    if ($ForceKillApps) { $argList += "-ForceKillApps" }

    Write-Step "Relaunching from safe location..."
    Start-Process -FilePath "powershell.exe" -ArgumentList $argList -Verb RunAs
    exit 0
}

# =============================================================================
# PREFLIGHT -- Working-Directory Escape
# =============================================================================

$normalizedPWD = Get-NormalizedPath (Get-Location).Path
if ($normalizedPWD.StartsWith($normalizedTarget)) {
    $escapeDir = Split-Path $TargetPath -Parent
    Write-Warn "Shell is cd'd inside the target -- escaping to $escapeDir"
    Set-Location $escapeDir
    Write-Ok "Moved to: $escapeDir"
}

# =============================================================================
# PREFLIGHT -- Locate handle.exe
# =============================================================================

Write-Step "Locating Sysinternals handle.exe..."
$HandleExePath = Find-HandleExe
if ($HandleExePath) {
    Write-Ok "Found: $HandleExePath"
} else {
    Write-Warn "handle.exe not found -- forced handle closing unavailable."
    Write-Detail "Install:  winget install SysInternals.Handle"
}

# =============================================================================
# KILL CHAIN
# =============================================================================

Write-Host ""
Write-Host ("=" * 60) -ForegroundColor DarkRed
Write-Host "  KILL CHAIN" -ForegroundColor Red
Write-Host ("=" * 60) -ForegroundColor DarkRed
Write-Host ""

# -- Phase 1: Scheduled Task -------------------------------------------------
Write-Step "Phase 1/5  Scheduled task '$TaskName'..."
$task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($task) {
    try {
        Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-Ok "Task '$TaskName' stopped and unregistered."
    } catch {
        Write-Warn "Could not remove task: $_"
    }
} else {
    Write-Detail "No task '$TaskName' found."
}

# -- Phase 2: AutoHotkey Processes -------------------------------------------
Write-Step "Phase 2/5  AutoHotkey processes..."
$ahkProcs = @(Get-Process -Name "AutoHotkey*" -ErrorAction SilentlyContinue)
if ($ahkProcs.Count -gt 0) {
    foreach ($proc in $ahkProcs) {
        try {
            Stop-Process -Id $proc.Id -Force -ErrorAction Stop
            Write-Ok ("  Killed " + $proc.ProcessName + " (PID:" + $proc.Id + ")")
        } catch {
            Write-Warn ("  Could not kill PID " + $proc.Id)
        }
    }
    Start-Sleep -Milliseconds 500
} else {
    Write-Detail "None running."
}

# -- Phase 3: IDE File-Watchers ---------------------------------------------
Write-Step "Phase 3/5  IDE file-watchers..."

$lockingIDEs = @()
foreach ($ideName in $IDEProcesses) {
    $ideProcs = @(Get-Process -Name $ideName -ErrorAction SilentlyContinue)
    foreach ($proc in $ideProcs) {
        try {
            $wmi = Get-CimInstance Win32_Process -Filter "ProcessId = $($proc.Id)" -ErrorAction SilentlyContinue
            if ($wmi -and $wmi.CommandLine -and $wmi.CommandLine.ToLowerInvariant().Contains($normalizedTarget)) {
                $lockingIDEs += [PSCustomObject]@{ Name = $proc.ProcessName; PID = $proc.Id }
            }
        } catch {}
    }
}

# Also note any running IDEs even without confirmed locks
$runningIDEs = @()
foreach ($ideName in $IDEProcesses) {
    if (@(Get-Process -Name $ideName -ErrorAction SilentlyContinue).Count -gt 0) {
        $runningIDEs += $ideName
    }
}

if ($lockingIDEs.Count -gt 0) {
    Write-Warn "IDEs locking target:"
    foreach ($ide in $lockingIDEs) { Write-Warn ("  " + $ide.Name + " (PID:" + $ide.PID + ")") }
    if ($ForceKillApps) {
        foreach ($ide in $lockingIDEs) {
            try {
                Stop-Process -Id $ide.PID -Force -ErrorAction Stop
                Write-Ok ("  Killed " + $ide.Name + " (PID:" + $ide.PID + ")")
            } catch {
                Write-Fail ("  Failed: " + $ide.Name + " PID:" + $ide.PID)
            }
        }
        Start-Sleep -Milliseconds 500
    } else {
        Write-Warn "  Close them manually or re-run with -ForceKillApps"
    }
} elseif ($runningIDEs.Count -gt 0) {
    Write-Warn ("Running IDEs that may hold invisible locks: " + ($runningIDEs -join ", "))
    if ($ForceKillApps) {
        foreach ($name in $runningIDEs) {
            Stop-Process -Name $name -Force -ErrorAction SilentlyContinue
            Write-Ok "  Killed all $name processes."
        }
        Start-Sleep -Milliseconds 500
    } else {
        Write-Detail "If deletion fails, re-run with -ForceKillApps"
    }
} else {
    Write-Detail "None detected."
}

# -- Phase 4: Explorer Windows ----------------------------------------------
Write-Step "Phase 4/5  Explorer windows..."
try {
    $shell = New-Object -ComObject Shell.Application
    $redirected = 0
    foreach ($w in $shell.Windows()) {
        try {
            $url = $w.LocationURL
            if (-not $url) { continue }
            $epath = [Uri]::UnescapeDataString($url) -replace '^file:///', '' -replace '/', '\'
            if ((Get-NormalizedPath $epath).StartsWith($normalizedTarget)) {
                $w.Navigate("C:\")
                $redirected++
            }
        } catch {}
    }
    if ($redirected -gt 0) {
        Write-Ok "Redirected $redirected Explorer window(s) away from target."
    } else {
        Write-Detail "None browsing target."
    }
} catch {
    Write-Detail "Could not enumerate Explorer windows."
}

# -- Phase 5: Force-Close Handles via handle.exe ----------------------------
Write-Step "Phase 5/5  Force-closing file handles..."
if ($HandleExePath) {
    $locks = Get-LockingHandles $HandleExePath $TargetPath
    if ($locks.Count -gt 0) {
        Write-Warn ("Found " + $locks.Count + " open handle(s):")
        foreach ($h in $locks) { Write-Detail $h.Line }
        Write-Host ""
        $closed = Close-AllLockingHandles $HandleExePath $TargetPath
        Write-Ok ("Closed " + $closed + "/" + $locks.Count + " handle(s).")
        Start-Sleep -Milliseconds 500
    } else {
        Write-Ok "No open handles -- path is clear."
    }
} else {
    Write-Warn "Skipped (handle.exe unavailable)."
}

# =============================================================================
# DESTRUCTION
# =============================================================================

Write-Host ""
Write-Host ("=" * 60) -ForegroundColor DarkRed
Write-Host "  DESTRUCTION" -ForegroundColor Red
Write-Host ("=" * 60) -ForegroundColor DarkRed
Write-Host ""

[System.GC]::Collect()
[System.GC]::WaitForPendingFinalizers()

$attempt = 0
$success = $false

while ($attempt -lt $MaxRetries -and -not $success) {
    $attempt++
    Write-Step "Attempt $attempt/$MaxRetries..."

    try {
        Remove-Item -Path $TargetPath -Recurse -Force -ErrorAction Stop
        $success = $true
    } catch [System.IO.IOException] {
        Write-Warn "  Failed: $($_.Exception.Message)"
        if ($attempt -lt $MaxRetries) {
            [System.GC]::Collect()
            [System.GC]::WaitForPendingFinalizers()
            if ($HandleExePath) {
                $reClosed = Close-AllLockingHandles $HandleExePath $TargetPath
                if ($reClosed -gt 0) { Write-Ok ("  Re-closed " + $reClosed + " respawned handle(s).") }
            }
            Start-Sleep -Seconds $RetryDelaySec
        }
    } catch {
        Write-Warn "  Failed: $($_.Exception.GetType().Name) -- $($_.Exception.Message)"
        if ($attempt -lt $MaxRetries) {
            Start-Sleep -Seconds $RetryDelaySec
        }
    }
}

# =============================================================================
# RESULT
# =============================================================================

Write-Host ""
Write-Host ("=" * 60) -ForegroundColor DarkRed

if ($success) {
    Write-Host ""
    Write-Host "  ____   ___  _   _ _____" -ForegroundColor Green
    Write-Host " |  _ \ / _ \| \ | | ____|" -ForegroundColor Green
    Write-Host " | | | | | | |  \| |  _|" -ForegroundColor Green
    Write-Host " | |_| | |_| | |\  | |___" -ForegroundColor Green
    Write-Host " |____/ \___/|_| \_|_____|" -ForegroundColor Green
    Write-Host ""
    Write-Ok "Directory obliterated: $TargetPath"
    Write-Detail "WinHypr has been fully purged from this system."

    # Clean up the temp copy if we self-relocated
    if ($_Relocated -and $PSCommandPath) {
        Remove-Item $PSCommandPath -Force -ErrorAction SilentlyContinue
        Write-Detail "Cleaned up temp script copy."
    }
} else {
    Write-Host ""
    Write-Fail "DELETION FAILED after $MaxRetries attempts."
    Write-Host ""

    if ($HandleExePath) {
        Write-Step "Post-mortem..."
        $remaining = Get-LockingHandles $HandleExePath $TargetPath
        if ($remaining.Count -gt 0) {
            foreach ($h in $remaining) { Write-Host "  $($h.Line)" -ForegroundColor Yellow }
            Write-Host ""
            $sysProcs = @($remaining | Where-Object {
                $_.Process -eq "System" -or $_.Process -eq "csrss.exe" -or
                $_.Process -eq "smss.exe" -or $_.Process -eq "wininit.exe"
            })
            if ($sysProcs.Count -gt 0) {
                Write-Fail "Locks held by protected system processes -- reboot required."
            } else {
                Write-Warn "Kill the above processes, then re-run nuke.ps1"
            }
        } else {
            Write-Detail "No handles reported. Try manual deletion:"
            Write-Detail ("  Remove-Item '" + $TargetPath + "' -Recurse -Force")
        }
    } else {
        Write-Warn "Install handle.exe for better diagnostics:"
        Write-Detail "  winget install SysInternals.Handle"
    }
}

Write-Host ""
Write-Host ("=" * 60) -ForegroundColor DarkRed
Write-Host ""
Write-Host "Press any key to exit..." -ForegroundColor DarkGray
$null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')

