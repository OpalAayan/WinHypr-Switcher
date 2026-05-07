; =============================================================================
; WinHypr.ahk — Backend API for Win-Hypr Virtual Desktop Manager
; =============================================================================
; A lightweight, zero-GUI virtual desktop manager for Windows 11.
; This file exposes the backend API — hotkeys are defined in keybinds.ahk.
;
; Architecture:
;   VirtualDesktopAccessor.dll  →  DLL wrappers (0→1 index bridge)
;                               →  Smart logic (SwitchToDesktop, MoveActiveToDesktop)
;                               →  Safety layer (debounce, spam lock)
;
; Usage: #Include this file from keybinds.ahk. Do not run directly.
; =============================================================================

#Requires AutoHotkey v2.0
#SingleInstance Force
#WinActivateForce           ; Aggressive focus stealing — needed for cross-desktop activation

; =============================================================================
; VERSION
; =============================================================================

global WINHY_VERSION := "1.0.0"

; =============================================================================
; DLL LOADING
; =============================================================================

global hVDA := DllCall("LoadLibrary", "Str", A_ScriptDir . "\VirtualDesktopAccessor.dll", "Ptr")

if (!hVDA) {
    MsgBox("FATAL: Failed to load VirtualDesktopAccessor.dll from:`n" . A_ScriptDir, "Win-Hypr — Error", "Icon!")
    ExitApp()
}

OutputDebug("[Win-Hypr v" . WINHY_VERSION . "] DLL loaded (handle: " . Format("0x{:X}", hVDA) . ")")

; =============================================================================
; DLL FUNCTION POINTERS
; =============================================================================
; Cached at startup via GetProcAddress. These raw pointers are invoked with
; DllCall(ptr, ...) for maximum performance — no string lookup per call.
; =============================================================================

global pGetDesktopCount          := DllCall("GetProcAddress", "Ptr", hVDA, "AStr", "GetDesktopCount", "Ptr")
global pGetCurrentDesktopNumber  := DllCall("GetProcAddress", "Ptr", hVDA, "AStr", "GetCurrentDesktopNumber", "Ptr")
global pGoToDesktopNumber        := DllCall("GetProcAddress", "Ptr", hVDA, "AStr", "GoToDesktopNumber", "Ptr")
global pMoveWindowToDesktopNumber := DllCall("GetProcAddress", "Ptr", hVDA, "AStr", "MoveWindowToDesktopNumber", "Ptr")

; Validate all exports resolved — fail hard if any are missing
for name, ptr in Map(
    "GetDesktopCount",          pGetDesktopCount,
    "GetCurrentDesktopNumber",  pGetCurrentDesktopNumber,
    "GoToDesktopNumber",        pGoToDesktopNumber,
    "MoveWindowToDesktopNumber", pMoveWindowToDesktopNumber
) {
    if (!ptr) {
        MsgBox("FATAL: Could not resolve DLL export: " . name . "`n`nIs VirtualDesktopAccessor.dll compatible with this Windows build?", "Win-Hypr — Error", "Icon!")
        ExitApp()
    }
    OutputDebug("[Win-Hypr] Resolved: " . name . " -> " . Format("0x{:X}", ptr))
}

; =============================================================================
; CONSTANTS
; =============================================================================

global DEBOUNCE_MS     := 50    ; Sleep after DLL calls to prevent Explorer crashes
global CREATE_DELAY_MS := 250   ; Sleep after Win+Ctrl+D to let the OS animation settle
global isSwitching     := false ; Global lock — prevents input spam during transitions

; =============================================================================
; DLL WRAPPER FUNCTIONS (1-indexed public API → 0-indexed DLL bridge)
; =============================================================================
; The DLL uses 0-indexed desktops (Desktop 1 = index 0).
; All public functions accept 1-indexed numbers and translate internally.
; Callers never need to think about zero-indexing.
; =============================================================================

/**
 * Returns the total number of virtual desktops.
 * @returns {Integer} Desktop count (a count, not an index — no translation)
 */
GetDesktopCount() {
    count := DllCall(pGetDesktopCount, "Int")
    Sleep(DEBOUNCE_MS)
    return count
}

/**
 * Returns the current desktop number (1-indexed).
 * @returns {Integer} Current desktop (1-based)
 */
GetCurrentDesktopNumber() {
    zeroIndexed := DllCall(pGetCurrentDesktopNumber, "Int")
    Sleep(DEBOUNCE_MS)
    return zeroIndexed + 1
}

/**
 * Switches to the specified desktop (raw — no auto-creation).
 * @param {Integer} num - 1-indexed desktop number
 */
GoToDesktopNumber(num) {
    DllCall(pGoToDesktopNumber, "Int", num - 1)
    Sleep(DEBOUNCE_MS)
}

/**
 * Moves a window (by HWND) to the specified desktop.
 * @param {Integer} hwnd - Window handle
 * @param {Integer} num  - 1-indexed target desktop number
 */
MoveWindowToDesktopNumber(hwnd, num) {
    DllCall(pMoveWindowToDesktopNumber, "Ptr", hwnd, "Int", num - 1)
    Sleep(DEBOUNCE_MS)
}

/**
 * Creates a new virtual desktop using native Windows shortcut (Win+Ctrl+D).
 *
 * NOTE: The DLL's CreateDesktop export causes 0xc0000005 access violations,
 * so we bypass it entirely and simulate the OS-native keystroke instead.
 * The 250ms sleep is critical — Windows needs time to process the desktop
 * creation animation before another keystroke can safely fire.
 */
CreateDesktop() {
    Send("{LWin down}{LCtrl down}d{LCtrl up}{LWin up}")
    Sleep(CREATE_DELAY_MS)
}

; =============================================================================
; SMART LOGIC FUNCTIONS
; =============================================================================

/**
 * SwitchToDesktop — Intelligently switches to the target desktop.
 *
 * If the target doesn't exist, calculates the exact number of desktops
 * needed and creates them in a deterministic loop (no re-querying the OS
 * mid-loop, which caused the overshoot race condition in earlier versions).
 *
 * @param {Integer} num - 1-indexed target desktop (must be >= 1)
 */
SwitchToDesktop(num) {
    if (num < 1) {
        OutputDebug("[Win-Hypr] SwitchToDesktop: Invalid target " . num . " (must be >= 1)")
        return
    }

    ; Spam guard — drop input while a transition is already running
    if (isSwitching) {
        OutputDebug("[Win-Hypr] SwitchToDesktop: BLOCKED (transition in progress)")
        return
    }
    global isSwitching := true

    try {
        current := GetCurrentDesktopNumber()
        if (current == num) {
            OutputDebug("[Win-Hypr] SwitchToDesktop: Already on desktop " . num)
            return
        }

        ; Deterministic creation — calculate deficit once, loop exactly that many times.
        ; Do NOT re-query GetDesktopCount() inside the loop: the OS lags behind the
        ; keystroke, causing the old while-loop to overshoot and create extra desktops.
        count := GetDesktopCount()
        if (num > count) {
            needed := num - count
            OutputDebug("[Win-Hypr] SwitchToDesktop: Creating " . needed . " desktop(s) (" . count . " → " . num . ")")
            Loop needed {
                CreateDesktop()
            }
        }

        OutputDebug("[Win-Hypr] SwitchToDesktop: Switching " . current . " → " . num)
        GoToDesktopNumber(num)
        _FocusForemostWindow()
    } finally {
        global isSwitching := false
    }
}

/**
 * MoveActiveToDesktop — Moves the active window to the target desktop
 * and follows it, preserving focus.
 *
 * Uses the same deterministic creation logic as SwitchToDesktop.
 *
 * @param {Integer} num - 1-indexed target desktop (must be >= 1)
 */
MoveActiveToDesktop(num) {
    if (num < 1) {
        OutputDebug("[Win-Hypr] MoveActiveToDesktop: Invalid target " . num . " (must be >= 1)")
        return
    }

    ; Spam guard
    if (isSwitching) {
        OutputDebug("[Win-Hypr] MoveActiveToDesktop: BLOCKED (transition in progress)")
        return
    }
    global isSwitching := true

    try {
        ; Grab active window
        try {
            hwnd := WinGetID("A")
        } catch {
            OutputDebug("[Win-Hypr] MoveActiveToDesktop: No active window found")
            return
        }

        if (!hwnd) {
            OutputDebug("[Win-Hypr] MoveActiveToDesktop: Active window HWND is null")
            return
        }

        OutputDebug("[Win-Hypr] MoveActiveToDesktop: HWND " . hwnd . " → desktop " . num)

        ; Deterministic creation (same pattern as SwitchToDesktop)
        count := GetDesktopCount()
        if (num > count) {
            needed := num - count
            OutputDebug("[Win-Hypr] MoveActiveToDesktop: Creating " . needed . " desktop(s) (" . count . " → " . num . ")")
            Loop needed {
                CreateDesktop()
            }
        }

        ; Move window, follow it, re-activate
        MoveWindowToDesktopNumber(hwnd, num)
        GoToDesktopNumber(num)

        Sleep(DEBOUNCE_MS)
        try {
            WinActivate("ahk_id " . hwnd)
        } catch {
            OutputDebug("[Win-Hypr] MoveActiveToDesktop: Could not re-activate HWND " . hwnd)
        }
    } finally {
        global isSwitching := false
    }
}

; =============================================================================
; INTERNAL HELPERS
; =============================================================================

/**
 * _FocusForemostWindow — After a desktop switch, briefly focuses the taskbar
 * to suppress flashing app icons, then re-activates the topmost window.
 */
_FocusForemostWindow() {
    taskbarHwnd := DllCall("FindWindow", "Str", "Shell_TrayWnd", "Ptr", 0, "Ptr")
    if (taskbarHwnd) {
        DllCall("SetForegroundWindow", "Ptr", taskbarHwnd)
    }

    Sleep(DEBOUNCE_MS)

    try {
        hwnd := WinGetID("A")
        if (hwnd) {
            WinActivate("ahk_id " . hwnd)
        }
    } catch {
        ; Empty desktop — nothing to focus
    }
}

; =============================================================================
; STARTUP
; =============================================================================

OutputDebug("[Win-Hypr v" . WINHY_VERSION . "] Desktops: " . GetDesktopCount() . " | Current: " . GetCurrentDesktopNumber() . " | Ready")
