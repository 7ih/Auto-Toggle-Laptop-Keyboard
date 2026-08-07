#Requires AutoHotkey v2.0
#SingleInstance Force
#include Lib\AutoHotInterception.ahk

; ==========================================
; GLOBALS & PATHS
; ==========================================
global ConfigFile := A_ScriptDir "\config.ini"
global InternalKbdID := 0
global InternalKbdHandle := ""
global InternalMouseID := 0
global InternalMouseHandle := ""
global isBlocked := false
global isMouseBlocked := false
global ShowNotifications := true
global HideTrayIconSetting := false
global RunOnStartup := false
global KeepInternalKeyboardEnabled := false
global KeepInternalMouseEnabled := false

; Auto-elevate to Administrator (Required for Interception kernel driver)
if not A_IsAdmin {
    Run('*RunAs "' A_ScriptFullPath '"')
    ExitApp()
}

global AHI := AutoHotInterception()
global WMI := ComObjGet("winmgmts:{impersonationLevel=impersonate}!\\.\root\cimv2")

; ==========================================
; LOAD CONFIGURATION
; ==========================================
if FileExist(ConfigFile) {
    InternalKbdHandle := IniRead(ConfigFile, "Settings", "DeviceHandle", "")
    InternalMouseHandle := IniRead(ConfigFile, "Settings", "InternalMouseHandle", "")
    ShowNotifications := Number(IniRead(ConfigFile, "Settings", "ShowNotifications", "1"))
    HideTrayIconSetting := Number(IniRead(ConfigFile, "Settings", "HideTrayIcon", "0"))
    KeepInternalKeyboardEnabled := Number(IniRead(ConfigFile, "Settings", "KeepInternalKeyboardEnabled", "0"))
    KeepInternalMouseEnabled := Number(IniRead(ConfigFile, "Settings", "KeepInternalMouseEnabled", "0"))
}

RunOnStartup := IsStartupTaskPresent()

; Apply tray icon visibility immediately
if (HideTrayIconSetting) {
    A_IconHidden := true
}

; ==========================================
; SYSTEM TRAY MENU SETUP
; ==========================================
TraySetIcon("icon.ico")
A_TrayMenu.Add()
A_TrayMenu.Add("Show Popup Notifications", MenuToggleNotifications)
A_TrayMenu.Add("Run on Startup", MenuToggleRunOnStartup)
A_TrayMenu.Add("Keep Internal Keyboard Enabled", MenuToggleKeepKeyboard)
A_TrayMenu.Add("Keep Internal Mouse Enabled", MenuToggleKeepMouse)
A_TrayMenu.Add("Recalibrate Internal Keyboard", MenuRecalibrateKeyboard)
A_TrayMenu.Add("Recalibrate Internal Mouse", MenuRecalibrateMouse)
A_TrayMenu.Add("Permanently Hide Tray Icon", MenuHideTrayIcon)

; Set checkmark state for popup notifications
if (ShowNotifications) {
    A_TrayMenu.Check("Show Popup Notifications")
} else {
    A_TrayMenu.Uncheck("Show Popup Notifications")
}

if (RunOnStartup) {
    A_TrayMenu.Check("Run on Startup")
} else {
    A_TrayMenu.Uncheck("Run on Startup")
}

if (KeepInternalKeyboardEnabled) {
    A_TrayMenu.Check("Keep Internal Keyboard Enabled")
} else {
    A_TrayMenu.Uncheck("Keep Internal Keyboard Enabled")
}

if (KeepInternalMouseEnabled) {
    A_TrayMenu.Check("Keep Internal Mouse Enabled")
} else {
    A_TrayMenu.Uncheck("Keep Internal Mouse Enabled")
}

; ==========================================
; MAIN INIT LOGIC
; ==========================================
Persistent()

; Find AHI slot for the saved hardware handle
if (InternalKbdHandle != "") {
    InternalKbdID := FindIDByHandle(InternalKbdHandle)
}
if (InternalMouseHandle != "") {
    InternalMouseID := FindIDByHandle(InternalMouseHandle)
}

; If no keyboard handle found, run keyboard calibration; mouse can be calibrated later
if (InternalKbdID == 0) {
    CalibrateKeyboard()
} else {
    StartAutoToggle()
}

; ==========================================
; TRAY MENU ACTIONS
; ==========================================
MenuToggleNotifications(ItemName, ItemPos, MyMenu) {
    global ShowNotifications, ConfigFile
    ShowNotifications := !ShowNotifications
    
    A_TrayMenu.ToggleCheck(ItemName)
    IniWrite(ShowNotifications ? "1" : "0", ConfigFile, "Settings", "ShowNotifications")
}

MenuHideTrayIcon(ItemName, ItemPos, MyMenu) {
    global ConfigFile
    result := MsgBox("This will hide the script icon from the system tray.`n`nThe script will keep running silently in the background.`n`nTo bring the icon back later, open 'config.ini' in the app folder, change 'HideTrayIcon=1' to '0', and restart the app.`n`nHide icon now?", "Hide Tray Icon", "4 4096")
    
    if (result == "Yes") {
        IniWrite("1", ConfigFile, "Settings", "HideTrayIcon")
        A_IconHidden := true
    }
}

MenuToggleKeepKeyboard(ItemName, ItemPos, MyMenu) {
    global KeepInternalKeyboardEnabled, ConfigFile
    KeepInternalKeyboardEnabled := !KeepInternalKeyboardEnabled
    A_TrayMenu.ToggleCheck(ItemName)
    IniWrite(KeepInternalKeyboardEnabled ? "1" : "0", ConfigFile, "Settings", "KeepInternalKeyboardEnabled")
    CheckDevices()
}

MenuToggleKeepMouse(ItemName, ItemPos, MyMenu) {
    global KeepInternalMouseEnabled, ConfigFile
    KeepInternalMouseEnabled := !KeepInternalMouseEnabled
    A_TrayMenu.ToggleCheck(ItemName)
    IniWrite(KeepInternalMouseEnabled ? "1" : "0", ConfigFile, "Settings", "KeepInternalMouseEnabled")
    CheckDevices()
}

MenuToggleRunOnStartup(ItemName, ItemPos, MyMenu) {
    global RunOnStartup, ConfigFile
    RunOnStartup := !RunOnStartup
    A_TrayMenu.ToggleCheck(ItemName)

    if (RunOnStartup) {
        if (!CreateStartupTask()) {
            MsgBox("Unable to create startup task. Run on startup will remain disabled.", "Error", "16")
            RunOnStartup := false
            A_TrayMenu.Uncheck(ItemName)
        }
    } else {
        DeleteStartupTask()
    }

    IniWrite(RunOnStartup ? "1" : "0", ConfigFile, "Settings", "RunOnStartup")
}

MenuRecalibrateKeyboard(ItemName, ItemPos, MyMenu) {
    CalibrateKeyboard()
}

MenuRecalibrateMouse(ItemName, ItemPos, MyMenu) {
    CalibrateMouse()
}

; ==========================================
; CALIBRATION LOGIC
; ==========================================
CalibrateKeyboard() {
    global isBlocked, InternalKbdID
    
    ; Unblock keyboard if it was previously blocked
    if (isBlocked && InternalKbdID != 0) {
        try AHI.UnsubscribeKeyboard(InternalKbdID)
        isBlocked := false
    }

    MsgBox("After pressing OK, Please press ANY KEY on your BUILT-IN LAPTOP KEYBOARD to calibrate (you will only have to do this once).", "Keyboard Calibration", "4096")
    
    ; Temporarily listen to all keyboard slots (IDs 1 through 10)
    Loop 10 {
        try AHI.SubscribeKeyboard(A_Index, false, CalibrationCallback.Bind(A_Index))
    }
}

CalibrationCallback(id, code, state) {
    global InternalKbdID, InternalKbdHandle, ConfigFile

    ; Ignore key releases
    if (!state) {
        return
    }
    
    ; Stop calibration listener
    Loop 10 {
        try AHI.UnsubscribeKeyboard(A_Index)
    }
    
    devList := AHI.GetDeviceList()
    InternalKbdID := id
    InternalKbdHandle := devList[id].Handle
    
    ; Save hardware handle to config.ini
    IniWrite(InternalKbdHandle, ConfigFile, "Settings", "DeviceHandle")
    
    MsgBox("Captured Laptop Keyboard Handle:`n" InternalKbdHandle "`n`nRecalibration is available in the system tray.", "Setup Complete", "4096")
    
    StartAutoToggle()
}

CalibrateMouse() {
    global isMouseBlocked, InternalMouseID

    if (isMouseBlocked && InternalMouseID != 0) {
        try AHI.UnsubscribeMouseButtons(InternalMouseID)
        try AHI.UnsubscribeMouseMoveRelative(InternalMouseID)
        try AHI.UnsubscribeMouseMoveAbsolute(InternalMouseID)
        isMouseBlocked := false
    }

    MsgBox("After pressing OK, please press ANY BUTTON on your BUILT-IN TRACKPAD or internal pointing device to calibrate.", "Mouse Calibration", "4096")
    Loop 10 {
        try AHI.SubscribeMouseButtons(A_Index, false, MouseCalibrationCallback.Bind(A_Index))
    }
}

MouseCalibrationCallback(id, code, state) {
    global InternalMouseID, InternalMouseHandle, ConfigFile

    if (!state) {
        return
    }

    Loop 10 {
        try AHI.UnsubscribeMouseButtons(A_Index)
    }

    devList := AHI.GetDeviceList()
    InternalMouseID := id
    InternalMouseHandle := devList[id].Handle
    IniWrite(InternalMouseHandle, ConfigFile, "Settings", "InternalMouseHandle")
    MsgBox("Captured Internal Mouse Handle:`n" InternalMouseHandle "`n`nRecalibration is available in the system tray.", "Setup Complete", "4096")
    StartAutoToggle()
}

FindIDByHandle(targetHandle) {
    devList := AHI.GetDeviceList()
    for id, dev in devList {
        if (id <= 10 && dev.Handle == targetHandle) {
            return id
        }
    }
    return 0
}

IsStartupTaskPresent() {
    taskName := "AutoToggleInternalKeyboard"
    exitCode := RunWait('cmd /c schtasks /Query /TN "' taskName '" >nul 2>&1', "", "Hide")
    if (exitCode != 0) {
        return false
    }

    ; Check if .exe was moved
    currentPath := A_ScriptFullPath
    taskPath := GetStartupTaskPath(taskName)
    if (taskPath != "" && taskPath != currentPath) {
        UpdateStartupTaskPath(taskName, currentPath)
    }

    return true
}

GetStartupTaskPath(taskName) {
    output := ""
    exitCode := RunWait('cmd /c schtasks /Query /V /FO LIST /TN "' taskName '" 2^>nul', output, "Hide")
    if (exitCode != 0) {
        return ""
    }

    for line in StrSplit(output, "`n") {
        if (SubStr(line, 1, 12) == "Task To Run:") {
            return Trim(SubStr(line, 13))
        }
    }

    return ""
}

UpdateStartupTaskPath(taskName, newPath) {
    cmd := 'cmd /c schtasks /Change /TN "' . taskName . '" /TR "' . newPath . '" >nul 2>&1'
    exitCode := RunWait(cmd, "", "Hide")
    return exitCode == 0
}

CreateStartupTask() {
    taskName := "AutoToggleInternalKeyboard"
    taskPath := A_ScriptFullPath
    cmd := 'cmd /c schtasks /Create /TN "' . taskName . '" /TR "' . taskPath . '" /SC ONLOGON /RL HIGHEST /F >nul 2>&1'
    exitCode := RunWait(cmd, "", "Hide")
    return exitCode == 0
}

DeleteStartupTask() {
    taskName := "AutoToggleInternalKeyboard"
    cmd := 'cmd /c schtasks /Delete /TN "' . taskName . '" /F >nul 2>&1'
    exitCode := RunWait(cmd, "", "Hide")
    return exitCode == 0
}

; ==========================================
; AUTO-TOGGLE MONITORING LOGIC
; ==========================================
StartAutoToggle() {
    CheckKeyboards()

    static Sink := ComObject("WbemScripting.SWbemSink")
    ComObjConnect(Sink, "WMIEvent_")
    WMI.ExecNotificationQueryAsync(Sink, "SELECT * FROM Win32_DeviceChangeEvent")
}

WMIEvent_OnObjectReady(params*) {
    CheckKeyboards()
}

CheckDevices() {
    global isBlocked, isMouseBlocked, InternalKbdID, InternalKbdHandle, InternalMouseID, InternalMouseHandle, KeepInternalKeyboardEnabled, KeepInternalMouseEnabled
    
    if (InternalKbdID == 0 || AHI.GetDeviceList()[InternalKbdID].Handle != InternalKbdHandle) {
        InternalKbdID := FindIDByHandle(InternalKbdHandle)
    }
    if (InternalMouseID == 0 || AHI.GetDeviceList()[InternalMouseID].Handle != InternalMouseHandle) {
        InternalMouseID := FindIDByHandle(InternalMouseHandle)
    }

    externalKeyboardConnected := false
    externalMouseConnected := false

    if (InternalKbdID != 0) {
        query := "SELECT * FROM Win32_Keyboard"
        kbdDevices := WMI.ExecQuery(query)
        for dev in kbdDevices {
            if InStr(dev.PNPDeviceID, "ACPI\\") {
                continue
            }
            if InStr(InternalKbdHandle, dev.PNPDeviceID) {
                continue
            }
            externalKeyboardConnected := true
            break
        }
    }

    if (InternalMouseID != 0) {
        query := "SELECT * FROM Win32_PointingDevice"
        mouseDevices := WMI.ExecQuery(query)
        for dev in mouseDevices {
            if InStr(dev.PNPDeviceID, "ACPI\\") {
                continue
            }
            if InStr(InternalMouseHandle, dev.PNPDeviceID) {
                continue
            }
            externalMouseConnected := true
            break
        }
    }

    if (externalKeyboardConnected && !KeepInternalKeyboardEnabled) {
        if (!isBlocked) {
            AHI.SubscribeKeyboard(InternalKbdID, true, (*)=>0)
            isBlocked := true
            ShowOSD("External Keyboard Detected`nInternal Keyboard BLOCKED")
        }
    } else {
        if (isBlocked) {
            AHI.UnsubscribeKeyboard(InternalKbdID)
            isBlocked := false
            ShowOSD("External Keyboard Disconnected`nInternal Keyboard ACTIVE")
        }
    }

    if (externalMouseConnected && !KeepInternalMouseEnabled) {
        if (!isMouseBlocked) {
            BlockInternalMouse()
            ShowOSD("External Mouse Detected`nInternal Trackpad BLOCKED")
        }
    } else {
        if (isMouseBlocked) {
            UnblockInternalMouse()
            ShowOSD("External Mouse Disconnected`nInternal Trackpad ACTIVE")
        }
    }
}

BlockInternalMouse() {
    global isMouseBlocked, InternalMouseID
    if (InternalMouseID == 0) {
        return
    }
    try AHI.SubscribeMouseButtons(InternalMouseID, true, (*)=>0)
    try AHI.SubscribeMouseMoveRelative(InternalMouseID, true, (*)=>0)
    try AHI.SubscribeMouseMoveAbsolute(InternalMouseID, true, (*)=>0)
    isMouseBlocked := true
}

UnblockInternalMouse() {
    global isMouseBlocked, InternalMouseID
    if (InternalMouseID == 0) {
        return
    }
    try AHI.UnsubscribeMouseButtons(InternalMouseID)
    try AHI.UnsubscribeMouseMoveRelative(InternalMouseID)
    try AHI.UnsubscribeMouseMoveAbsolute(InternalMouseID)
    isMouseBlocked := false
}

ShowOSD(Message) {
    global ShowNotifications
    if (!ShowNotifications) {
        return
    }
    ToolTip(Message)
    SetTimer(() => ToolTip(), -2500)
}