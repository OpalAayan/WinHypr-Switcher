; =============================================================================
; keybinds.ahk — Win-Hypr Hotkey Configuration
; =============================================================================
; This is the entry point. Run this file (as Administrator) to start Win-Hypr.
; Edit the bindings below to customize your workflow.
;
; Modifier legend:
;   #  = Super (Win)      +  = Shift
;   ^  = Ctrl             !  = Alt
; =============================================================================

#Requires AutoHotkey v2.0
#SingleInstance Force

; Load the backend API
#Include WinHypr.ahk

; Startup confirmation (non-blocking, auto-dismisses)
TrayTip("Win-Hypr v" . WINHY_VERSION . " loaded`nDesktops: " . GetDesktopCount(), "Win-Hypr", "Iconi Mute")

; =============================================================================
; WORKSPACE NAVIGATION — Super + 1-9
; =============================================================================
; Jump directly to any workspace. If the workspace doesn't exist yet,
; it will be created automatically (Hyprland-style dynamic workspaces).
; =============================================================================

#1::SwitchToDesktop(1)
#2::SwitchToDesktop(2)
#3::SwitchToDesktop(3)
#4::SwitchToDesktop(4)
#5::SwitchToDesktop(5)
#6::SwitchToDesktop(6)
#7::SwitchToDesktop(7)
#8::SwitchToDesktop(8)
#9::SwitchToDesktop(9)

; =============================================================================
; WINDOW TELEPORT — Super + Shift + 1-9
; =============================================================================
; Move the active window to the target workspace and follow it.
; Focus is preserved on the moved window.
; =============================================================================

#+1::MoveActiveToDesktop(1)
#+2::MoveActiveToDesktop(2)
#+3::MoveActiveToDesktop(3)
#+4::MoveActiveToDesktop(4)
#+5::MoveActiveToDesktop(5)
#+6::MoveActiveToDesktop(6)
#+7::MoveActiveToDesktop(7)
#+8::MoveActiveToDesktop(8)
#+9::MoveActiveToDesktop(9)


; =============================================================================
; WORKSPACE CYCLING — Ctrl + Alt + Arrow Keys
; =============================================================================
; Hijacks Ctrl+Alt+Left/Right for native Windows desktop cycling.
; Nullifies Ctrl+Alt+Up/Down so they do absolutely nothing.
; =============================================================================

$^!Right::Send("{LCtrl down}{LWin down}{Right}{LWin up}{LCtrl up}")
$^!Left::Send("{LCtrl down}{LWin down}{Left}{LWin up}{LCtrl up}")

^!Up::return
^!Down::return

; =============================================================================
; SCREEN ORIENTATION — Super + Ctrl + Arrow Keys (Intel 4000HD) bhur
; =============================================================================
; Bypasses AHK to trigger the Intel Graphics rotation shortcuts natively.
; =============================================================================

$#^Up::Send("{LCtrl down}{LAlt down}{Up}{LAlt up}{LCtrl up}")
$#^Down::Send("{LCtrl down}{LAlt down}{Down}{LAlt up}{LCtrl up}")
$#^Left::Send("{LCtrl down}{LAlt down}{Left}{LAlt up}{LCtrl up}")
$#^Right::Send("{LCtrl down}{LAlt down}{Right}{LAlt up}{LCtrl up}")


; =============================================================================
; WORKSPACE DELETION — Super + Backspace
; =============================================================================
; Closes the current virtual desktop. Any open windows on this desktop 
; will automatically fall back to the previous desktop.
; =============================================================================

#Backspace::Send("{LCtrl down}{LWin down}{F4}{LWin up}{LCtrl up}")
#Delete::Send("{LCtrl down}{LWin down}{F4}{LWin up}{LCtrl up}")  ; Optional alternative

; =============================================================================
; WINDOW MANAGEMENT
; =============================================================================

; Super + Q — Close active window
#q::WinClose("A")

; Super + V — Toggle maximize / restore
#v::
{
    if WinGetMinMax("A") = 1
        WinRestore("A")
    else
        WinMaximize("A")
}

; =============================================================================
; Other custom Binds
; =============================================================================

; Ctrl + Alt + T - Open Windows Terminal
^!t::Run("wt.exe")
; Super + Shift + V - Open Windows ClipBoard 
#+v::Send "{LWin down}v{LWin up}"
