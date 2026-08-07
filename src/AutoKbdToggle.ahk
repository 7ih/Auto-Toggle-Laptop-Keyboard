#Requires AutoHotkey v2.0
#SingleInstance Force
#include Lib\AutoHotInterception.ahk

; Wait for Windows desktop/system tray to load before creating the icon
ProcessWait("explorer.exe")

; ==========================================
; GLOBALS & ELEVATION
; ==========================================
if !A_IsAdmin {
    Run('*RunAs "' A_ScriptFullPath '"')
    ExitApp()
}

global ConfigFile := A_ScriptDir "\config.ini"
global InternalKbdID := 0, InternalKbdHandle := "", isBlocked := false
global AHI := AutoHotInterception()
global WMI := ComObjGet("winmgmts:{impersonationLevel=impersonate}!\\.\root\cimv2")

; Keep script running persistently in the background
Persistent()

; ==========================================
; LOAD CONFIG & INITIALIZE
; ==========================================
InternalKbdHandle := IniRead(ConfigFile, "Settings", "DeviceHandle", "")
global ShowNotifications := Number(IniRead(ConfigFile, "Settings", "ShowNotifications", 1))
global HideTrayIconSetting := Number(IniRead(ConfigFile, "Settings", "HideTrayIcon", 0))
global RunOnStartup := Number(IniRead(ConfigFile, "Settings", "RunOnStartup", 0))
global KeepInternalKeyboardEnabled := Number(IniRead(ConfigFile, "Settings", "KeepInternalKeyboardEnabled", 0))

if (HideTrayIconSetting)
    A_IconHidden := true
if (RunOnStartup)
    SetStartupTask(true)

; ==========================================
; SYSTEM TRAY MENU
; ==========================================
global IconFile := A_ScriptDir "\icon.ico"
A_IconHidden := HideTrayIconSetting
SetTimer(InitTrayMenu, -1000)

InitTrayMenu(*) {
    static initialized := false
    if (initialized)
        return

    if !WinExist("ahk_class Shell_TrayWnd") {
        SetTimer(InitTrayMenu, -1000)
        return
    }

    initialized := true

    if FileExist(IconFile)
        TraySetIcon(IconFile)
    else
        TraySetIcon()

    A_IconTip := "Auto Toggle Laptop Keyboard"
    A_TrayMenu.Delete()

    A_TrayMenu.Add("Keep Internal Keyboard Enabled", ToggleKeepKbd)
    A_TrayMenu.Add("Recalibrate Internal Keyboard", (*) => CalibrateKeyboard())
    A_TrayMenu.Add()
    A_TrayMenu.Add("Run on Startup", ToggleStartup)
    A_TrayMenu.Add("Show Connection Notifications", ToggleNotify)
    A_TrayMenu.Add("Permanently Hide Tray Icon", HideTray)
    A_TrayMenu.Add()
    A_TrayMenu.Add("Exit", (*) => ExitApp())

    (KeepInternalKeyboardEnabled) && A_TrayMenu.Check("Keep Internal Keyboard Enabled")
    (RunOnStartup) && A_TrayMenu.Check("Run on Startup")
    (ShowNotifications) && A_TrayMenu.Check("Show Connection Notifications")
}

; ==========================================
; MAIN INIT LOGIC
; ==========================================
if (InternalKbdHandle != "")
    InternalKbdID := FindIDByHandle(InternalKbdHandle)

if (!InternalKbdID && TryAutoDetectInternalKeyboard())
    MsgBox("Automatic detection was attempted for the internal keyboard.`nIf it did not select the intended device, use the tray menu to recalibrate.", "Auto-detection", "4096")
else if (!InternalKbdID)
    CalibrateKeyboard()

StartAutoToggle()

; ==========================================
; TRAY MENU ACTIONS
; ==========================================
ToggleNotify(*) {
    global ShowNotifications := !ShowNotifications
    A_TrayMenu.ToggleCheck("Show Connection Notifications")
    IniWrite(ShowNotifications ? 1 : 0, ConfigFile, "Settings", "ShowNotifications")
}

ToggleKeepKbd(*) {
    global KeepInternalKeyboardEnabled := !KeepInternalKeyboardEnabled
    A_TrayMenu.ToggleCheck("Keep Internal Keyboard Enabled")
    IniWrite(KeepInternalKeyboardEnabled ? 1 : 0, ConfigFile, "Settings", "KeepInternalKeyboardEnabled")
    CheckDevices()
}

ToggleStartup(*) {
    global RunOnStartup := !RunOnStartup
    A_TrayMenu.ToggleCheck("Run on Startup")
    IniWrite(RunOnStartup ? 1 : 0, ConfigFile, "Settings", "RunOnStartup")
    SetStartupTask(RunOnStartup)
}

HideTray(*) {
    if MsgBox("This hides the script icon from the tray. The script will keep running in the background.`n`nTo bring it back, open 'config.ini', change 'HideTrayIcon=1' to '0', and restart.`n`nHide icon now?", "Hide Tray Icon", "4 4096") == "Yes" {
        IniWrite(1, ConfigFile, "Settings", "HideTrayIcon")
        A_IconHidden := true
    }
}

SetStartupTask(enable) {
    cmd := enable ? 'schtasks /Create /TN "\AutoToggleInternalKeyboard" /TR "\"' A_ScriptFullPath '\"" /SC ONLOGON /RL HIGHEST /F' 
                  : 'schtasks /Delete /TN "\AutoToggleInternalKeyboard" /F'
    RunWait(A_ComSpec " /c " cmd, "", "Hide")
}

; ==========================================
; CALIBRATION & AUTO-DETECT
; ==========================================
CalibrateKeyboard() {
    global isBlocked
    if (isBlocked && InternalKbdID)
        try AHI.UnsubscribeKeyboard(InternalKbdID), isBlocked := false
    
    for id, dev in AHI.GetDeviceList()
        try AHI.SubscribeKeyboard(id, false, CalibrationCallback.Bind(id))

    MsgBox("Please press ANY KEY on your BUILT-IN LAPTOP KEYBOARD to calibrate.", "Calibration", "4096")
}

CalibrationCallback(id, code, state) {
    global InternalKbdID, InternalKbdHandle
    if (!state)
        return ; Ignore key releases
    
    for currentId, dev in AHI.GetDeviceList()
        try AHI.UnsubscribeKeyboard(currentId)
    
    InternalKbdID := id, InternalKbdHandle := AHI.GetDeviceList()[id].Handle
    IniWrite(InternalKbdHandle, ConfigFile, "Settings", "DeviceHandle")
    
    if WinExist("Calibration ahk_class #32770") {
        WinClose("Calibration ahk_class #32770")
        WinWaitClose("Calibration ahk_class #32770", , 2)
    }
    
    MsgBox("Captured Handle:`n" InternalKbdHandle, "Setup Complete", "4096")
    StartAutoToggle()
}

TryAutoDetectInternalKeyboard() {
    global InternalKbdID, InternalKbdHandle
    devList := AHI.GetDeviceList()
    
    for dev in WMI.ExecQuery("SELECT * FROM Win32_Keyboard") {
        if InStr(dev.PNPDeviceID, "ACPI\") || InStr(dev.PNPDeviceID, "PNP") || InStr(dev.PNPDeviceID, "MSFT") {
            if (handle := FindHandleForWmiDevice(dev.PNPDeviceID, devList)) {
                InternalKbdHandle := handle, InternalKbdID := FindIDByHandle(handle)
                IniWrite(InternalKbdHandle, ConfigFile, "Settings", "DeviceHandle")
                return true
            }
        }
    }
    return false
}

FindHandleForWmiDevice(pnpId, devList) {
    ; 1. Translate squashed WMI formats (e.g. MSFT0001 -> VEN_MSFT&DEV_0001)
    if RegExMatch(pnpId, "(?i)(ACPI|HID)\\([A-Z]{4})([0-9A-Z]{4})", &m) {
        for id, dev in devList
            if InStr(dev.Handle, "VEN_" m[2]) && InStr(dev.Handle, "DEV_" m[3])
                return dev.Handle
    }
    ; 2. Standard USB VID/PID matching
    if RegExMatch(pnpId, "i)VID_([0-9A-F]{4})(?:.*PID_([0-9A-F]{4}))?", &m) {
        vid := Integer("0x" m[1]), pid := m[2] != "" ? Integer("0x" m[2]) : 0
        for id, dev in devList
            if dev.VID == vid && (!pid || dev.PID == pid)
                return dev.Handle
    }
    ; 3. Direct substring fallback
    for id, dev in devList
        if InStr(dev.Handle, pnpId) || InStr(pnpId, dev.Handle)
            return dev.Handle
    return ""
}

FindIDByHandle(targetHandle) {
    for id, dev in AHI.GetDeviceList()
        if (dev.Handle == targetHandle)
            return id
    return 0
}

; ==========================================
; MONITORING & TOGGLING
; ==========================================
StartAutoToggle() {
    static isStarted := false
    if (isStarted) {
        CheckDevices()
        return
    }
    isStarted := true
    CheckDevices()

    static Sink := ComObject("WbemScripting.SWbemSink")
    ComObjConnect(Sink, "WMIEvent_")
    WMI.ExecNotificationQueryAsync(Sink, "SELECT * FROM Win32_DeviceChangeEvent")
}

WMIEvent_OnObjectReady(params*) => CheckDevices()

CheckDevices() {
    global isBlocked, InternalKbdID
    devList := AHI.GetDeviceList()

    if (!InternalKbdID || !devList.Has(InternalKbdID) || devList[InternalKbdID].Handle != InternalKbdHandle)
        InternalKbdID := FindIDByHandle(InternalKbdHandle)

    extConnected := false

    if (InternalKbdID) {
        ; Check Interception's actual hardware list for any external keyboards
        for id, dev in devList {
            if (dev.IsMouse)
                continue
            if (id == InternalKbdID)
                continue

            ; If another physical keyboard ID exists, it's real
            extConnected := true
            break
        }
    }

    ; If the internal keyboard cannot be identified, do not assume an external keyboard is present.

    shouldBlock := extConnected && !KeepInternalKeyboardEnabled

    if (shouldBlock && !isBlocked) {
        AHI.SubscribeKeyboard(InternalKbdID, true, (*)=>0)
        isBlocked := true
        ShowOSD("External Keyboard Detected`nInternal Keyboard BLOCKED")
    } else if (!shouldBlock && isBlocked) {
        if (InternalKbdID)
            AHI.UnsubscribeKeyboard(InternalKbdID)
        isBlocked := false
        if (!extConnected) 
            ShowOSD("External Keyboard Disconnected`nInternal Keyboard ACTIVE")
    }
}

ShowOSD(Msg) {
    if (ShowNotifications) {
        ToolTip(Msg)
        SetTimer(ToolTip, -2500)
    }
}