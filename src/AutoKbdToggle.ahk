#Requires AutoHotkey v2.0
#SingleInstance Force

SetWorkingDir(A_ScriptDir)
#include Lib\AutoHotInterception.ahk

; ==========================================
; GLOBALS & ELEVATION
; ==========================================
if !A_IsAdmin {
    Run('*RunAs "' A_ScriptFullPath '"')
    ExitApp()
}

global ConfigFile := A_ScriptDir "\config.ini"
global InternalHandles := IniRead(ConfigFile, "Settings", "InternalHandles", "")
global isBlocked := false

global AHI := ""
try {
    AHI := AutoHotInterception()
} catch as err {
    MsgBox("Failed to initialize AutoHotInterception driver!`n`nError: " err.Message, "AHI Error", "16")
    ExitApp()
}

Persistent()

; ==========================================
; LOAD CONFIG & INITIALIZE
; ==========================================
global ShowNotifications := Number(IniRead(ConfigFile, "Settings", "ShowNotifications", 1))
global HideTrayIconSetting := Number(IniRead(ConfigFile, "Settings", "HideTrayIcon", 0))
global RunOnStartup := Number(IniRead(ConfigFile, "Settings", "RunOnStartup", 0))
global KeepInternalKeyboardEnabled := Number(IniRead(ConfigFile, "Settings", "KeepInternalKeyboardEnabled", 0))

global InternalIDs := []

; IF config has startup unchecked, query Task Scheduler to verify
if (!RunOnStartup && CheckTaskExists()) {
    global RunOnStartup := 1
    IniWrite(1, ConfigFile, "Settings", "RunOnStartup")
}

; Ensure task remains configured with correct script location and working directory
if (RunOnStartup)
    SetStartupTask(true)

if (InternalHandles == "") {
    CalibrateKeyboard()
} else {
    MapInternalIDs()
    StartAutoToggle()
}

; ==========================================
; SYSTEM TRAY MENU
; ==========================================
global IconFile := A_ScriptDir "\icon.ico"
A_IconHidden := HideTrayIconSetting ? true : false

SetTimer(InitTrayMenu, -1)

InitTrayMenu(*) {
    WinWait("ahk_class Shell_TrayWnd")

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
    cmd := enable ? 'schtasks /Create /TN "\AutoToggleInternalKeyboard" /TR "\"' A_ScriptFullPath '\"" /WorkingDirectory "' A_ScriptDir '" /SC ONLOGON /RL HIGHEST /F' 
                  : 'schtasks /Delete /TN "\AutoToggleInternalKeyboard" /F'
    RunWait(A_ComSpec " /c " cmd, "", "Hide")
}

CheckTaskExists() {
    ; Runs schtasks query silently; returns true (1) if task exists, false (0) if not
    return (RunWait(A_ComSpec ' /c schtasks /Query /TN "\AutoToggleInternalKeyboard"', "", "Hide") == 0)
}

; ==========================================
; MAP INTERNAL IDs (Called ONCE at Startup)
; ==========================================
MapInternalIDs() {
    global InternalIDs, InternalHandles
    InternalIDs := []
    
    if (InternalHandles == "")
        return

    devList := AHI.GetDeviceList()
    for id, dev in devList {
        if (dev.IsMouse || dev.Handle == "")
            continue
        if InStr(InternalHandles, dev.Handle) {
            InternalIDs.Push(id)
        }
    }
}

; ==========================================
; CALIBRATION (Captures Baseline)
; ==========================================
CalibrateKeyboard() {
    global InternalHandles, isBlocked

    if (isBlocked) {
        for index, kbdID in InternalIDs
            try AHI.UnsubscribeKeyboard(kbdID)
        isBlocked := false
    }

    MsgBox("1. UNPLUG all external USB/Bluetooth keyboards.`n2. Click OK.", "Auto Toggle Laptop Keyboard", "4096")

    ; 1. Map Interception Internal Handles
    InternalHandles := ""
    devList := AHI.GetDeviceList()
    for id, dev in devList {
        if (dev.IsMouse || dev.Handle == "")
            continue
        InternalHandles .= dev.Handle "|"
    }
    InternalHandles := Trim(InternalHandles, "|")
    IniWrite(InternalHandles, ConfigFile, "Settings", "InternalHandles")

    ; 2. Capture Baseline Raw Input Keyboard Count
    baselineCount := GetCurrentRawKeyboardCount()
    IniWrite(baselineCount, ConfigFile, "Settings", "BaselineRawCount")

    MsgBox("You may now plug your external keyboard back in.`nRecalibration is available in system tray options.", "Setup Complete", "4096")
    
    MapInternalIDs()
    StartAutoToggle()
}

; ==========================================
; HOTPLUG DETECTION (Windows Native)
; ==========================================
IsExternalKeyboardPresent() {
    baselineCount := Number(IniRead(ConfigFile, "Settings", "BaselineRawCount", 0))
    if (baselineCount == 0)
        return false

    currentCount := GetCurrentRawKeyboardCount()
    return (currentCount > baselineCount)
}

GetCurrentRawKeyboardCount() {
    static RIM_TYPEKEYBOARD := 1
    
    ; Dynamically determine struct size: 16 bytes on 64-bit, 8 bytes on 32-bit
    cbSize := (A_PtrSize == 8) ? 16 : 8
    
    count := 0
    ; First call with NULL pointer gets the total number of raw devices
    if (DllCall("User32\GetRawInputDeviceList", "Ptr", 0, "UInt*", &count, "UInt", cbSize) == -1)
        return 0
        
    if (count == 0)
        return 0

    ; Allocate the exact buffer size needed
    RAWINPUTDEVICELIST := Buffer(count * cbSize, 0)
    
    ; Second call actually fills the buffer with the device list
    if (DllCall("User32\GetRawInputDeviceList", "Ptr", RAWINPUTDEVICELIST, "UInt*", &count, "UInt", cbSize) == -1)
        return 0

    keyboardCount := 0
    Loop count {
        ; dwType memory offset is 8 on 64-bit, 4 on 32-bit
        dwTypeOffset := (A_PtrSize == 8) ? 8 : 4
        type := NumGet(RAWINPUTDEVICELIST, (A_Index - 1) * cbSize + dwTypeOffset, "UInt")
        
        if (type == RIM_TYPEKEYBOARD)
            keyboardCount++
    }

    return keyboardCount
}

; ==========================================
; SAFE MONITORING
; ==========================================
StartAutoToggle() {
    static isStarted := false
    if (isStarted) {
        CheckDevices()
        return
    }
    isStarted := true
    CheckDevices()

    OnMessage(0x0219, OnDeviceChange)
}

OnDeviceChange(wParam, lParam, msg, hwnd) {
    ; Any WM_DEVICECHANGE message triggers a re-evaluation after Windows PnP settles
    SetTimer(CheckDevices, -1500)
}

CheckDevices() {
    global isBlocked, InternalIDs, KeepInternalKeyboardEnabled

    if (InternalIDs.Length == 0)
        return

    extConnected := IsExternalKeyboardPresent()
    shouldBlock := extConnected && !KeepInternalKeyboardEnabled

    if (shouldBlock && !isBlocked) {
        for index, kbdID in InternalIDs
            try AHI.SubscribeKeyboard(kbdID, true, (*)=>0)
        isBlocked := true
        ShowOSD("External Keyboard Detected`nInternal Keyboards BLOCKED")
        
    } else if (!shouldBlock && isBlocked) {
        for index, kbdID in InternalIDs
            try AHI.UnsubscribeKeyboard(kbdID)
        isBlocked := false
        ShowOSD("External Keyboard Disconnected`nInternal Keyboards ACTIVE")
    }
}

ShowOSD(Msg) {
    if (ShowNotifications) {
        ToolTip(Msg)
        SetTimer(ToolTip, -2500)
    }
}