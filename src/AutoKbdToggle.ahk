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

if (RunOnStartup)
    SetStartupTask(true)

; Global array of internal device IDs captured ONCE at startup
global InternalIDs := []

if (InternalHandles == "") {
    CalibrateKeyboard()
} else {
    MapInternalIDs()
    StartAutoToggle()
}

if (RunOnStartup)
    SetStartupTask(true)    ; Makes sure task exists, and at correct location

; Launch the tray menu builder asynchronously in the background
SetTimer(InitTrayMenu, -1)

; ==========================================
; SYSTEM TRAY MENU
; ==========================================
global IconFile := A_ScriptDir "\icon.ico"
A_IconHidden := HideTrayIconSetting ? true : false
InitTrayMenu(*) {
    WinWait("ahk_class Shell_TrayWnd", "", 10)

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

; ==========================================
; MAP INTERNAL IDs (Called ONCE at Startup)
; ==========================================
MapInternalIDs() {
    global InternalIDs, InternalHandles
    InternalIDs := []
    
    if (InternalHandles == "")
        return

    ; Safe call to GetDeviceList ONCE during initialization
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
; CALIBRATION (Captures Baseline Raw Count)
; ==========================================
CalibrateKeyboard() {
    global InternalHandles, isBlocked

    if (isBlocked) {
        for index, kbdID in InternalIDs
            try AHI.UnsubscribeKeyboard(kbdID)
        isBlocked := false
    }

    MsgBox("1. UNPLUG all external USB/Bluetooth keyboards.`n2. Click OK.", "Auto Toggle Laptop Keyboard - Calibration", "4096")

    ; 1. Map Interception Internal Handles
    InternalHandles := ""
    devList := AHI.GetDeviceList()
    for id, dev in devList {
        if (dev.IsMouse || dev.Handle == "")
            continue
        InternalHandles .= dev.Handle "|"
    }
    IniWrite(InternalHandles, ConfigFile, "Settings", "InternalHandles")

    ; 2. Capture Baseline Raw Input Keyboard Count (while external is unplugged)
    baselineCount := GetCurrentRawKeyboardCount()
    IniWrite(baselineCount, ConfigFile, "Settings", "BaselineRawCount")

    MsgBox("Calibration Successful!`n`nYou may now plug your external keyboard back in.", "Setup Complete", "4096")
    
    MapInternalIDs()
    StartAutoToggle()
}

; ==========================================
; CRASH-PROOF HOTPLUG DETECTION
; ==========================================
IsExternalKeyboardPresentWindowsAPI() {
    baselineCount := Number(IniRead(ConfigFile, "Settings", "BaselineRawCount", 0))
    if (baselineCount == 0)
        return false

    currentCount := GetCurrentRawKeyboardCount()
    
    ; If Windows currently sees more raw keyboards than our baseline, an external device is attached
    return (currentCount > baselineCount)
}

GetCurrentRawKeyboardCount() {
    static RIM_TYPEKEYBOARD := 1
    
    count := 0
    if DllCall("User32\GetRawInputDeviceList", "Ptr", 0, "UInt*", &count, "UInt", 8) != 0
        return 0
        
    if (count == 0)
        return 0

    RAWINPUTDEVICELIST := Buffer(count * 8, 0)
    if DllCall("User32\GetRawInputDeviceList", "Ptr", RAWINPUTDEVICELIST, "UInt*", &count, "UInt", 8) == -1
        return 0

    keyboardCount := 0
    Loop count {
        type := NumGet(RAWINPUTDEVICELIST, (A_Index - 1) * 8 + 4, "UInt")
        if (type == RIM_TYPEKEYBOARD)
            keyboardCount++
    }

    return keyboardCount
}

; ==========================================
; SAFE MONITORING (No Interception Polling)
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
    if (wParam == 0x8000 || wParam == 0x8004) {
        ; Wait 1.5 seconds for Windows PnP to fully settle
        SetTimer(CheckDevices, -1500)
    }
}

; Check for external keyboards using Windows Native Raw Input API (100% safe for Interception)
CheckDevices() {
    global isBlocked, InternalIDs, KeepInternalKeyboardEnabled

    if (InternalIDs.Length == 0)
        return

    extConnected := IsExternalKeyboardPresentWindowsAPI()
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