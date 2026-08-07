#Requires AutoHotkey v2.0
#SingleInstance Force
#include Lib\AutoHotInterception.ahk

; ==========================================
; GLOBALS & PATHS
; ==========================================
global ConfigFile := A_ScriptDir "\config.ini"
global InternalKbdID := 0
global InternalKbdHandle := ""
global isBlocked := false
global ShowNotifications := true
global HideTrayIconSetting := false
global RunOnStartup := false

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
    ShowNotifications := Number(IniRead(ConfigFile, "Settings", "ShowNotifications", "1"))
    HideTrayIconSetting := Number(IniRead(ConfigFile, "Settings", "HideTrayIcon", "0"))
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
A_TrayMenu.Add("Recalibrate Internal Keyboard", MenuRecalibrate)
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

; ==========================================
; MAIN INIT LOGIC
; ==========================================
Persistent()

; Find AHI slot for the saved hardware handle
if (InternalKbdHandle != "") {
    InternalKbdID := FindIDByHandle(InternalKbdHandle)
}

; If no valid handle/ID found, run the calibration wizard
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

MenuRecalibrate(ItemName, ItemPos, MyMenu) {
    CalibrateKeyboard()
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
    global InternalKbdID := id
    global InternalKbdHandle := devList[id].Handle
    
    ; Save hardware handle to config.ini
    IniWrite(InternalKbdHandle, ConfigFile, "Settings", "DeviceHandle")
    
    MsgBox("Captured Laptop Keyboard Handle:`n" InternalKbdHandle "`n`nRecalibration is available in the system tray.", "Setup Complete", "4096")
    
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

CheckKeyboards() {
    global isBlocked, InternalKbdID, InternalKbdHandle
    
    if (InternalKbdID == 0 || AHI.GetDeviceList()[InternalKbdID].Handle != InternalKbdHandle) {
        InternalKbdID := FindIDByHandle(InternalKbdHandle)
    }

    if (InternalKbdID == 0) {
        return
    }

    query := "SELECT * FROM Win32_Keyboard"
    kbdDevices := WMI.ExecQuery(query)
    
    externalConnected := false
    for dev in kbdDevices {
        if InStr(dev.PNPDeviceID, "ACPI\") {
            continue
        }
            
        if InStr(InternalKbdHandle, dev.PNPDeviceID) {
            continue
        }
            
        externalConnected := true
        break
    }
    
    if (externalConnected) {
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
}

ShowOSD(Message) {
    global ShowNotifications
    if (!ShowNotifications) {
        return
    }
    ToolTip(Message)
    SetTimer(() => ToolTip(), -2500)
}