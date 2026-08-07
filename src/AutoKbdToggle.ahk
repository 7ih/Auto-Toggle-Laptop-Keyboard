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
global KeepInternalKeyboardEnabled := false

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
    KeepInternalKeyboardEnabled := Number(IniRead(ConfigFile, "Settings", "KeepInternalKeyboardEnabled", "0"))
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
A_TrayMenu.Add("Keep Internal Keyboard Enabled", MenuToggleKeepKeyboard)
A_TrayMenu.Add("Recalibrate Internal Keyboard", MenuRecalibrateKeyboard)
A_TrayMenu.Add()
A_TrayMenu.Add("Run on Startup", MenuToggleRunOnStartup)
A_TrayMenu.Add("Show Connection Notifications", MenuToggleNotifications)
A_TrayMenu.Add("Permanently Hide Tray Icon", MenuHideTrayIcon)

; Set checkmark state for tray menu items
if (ShowNotifications) {
    A_TrayMenu.Check("Show Connection Notifications")
} else {
    A_TrayMenu.Uncheck("Show Connection Notifications")
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

; ==========================================
; MAIN INIT LOGIC
; ==========================================
Persistent()

; Find AHI slot for the saved hardware handle
if (InternalKbdHandle != "") {
    InternalKbdID := FindIDByHandle(InternalKbdHandle)
}

keyboardAutoDetected := false

if (InternalKbdID == 0) {
    keyboardAutoDetected := TryAutoDetectInternalKeyboard()
    if (!keyboardAutoDetected) {
        CalibrateKeyboard()
    }
}

if (keyboardAutoDetected) {
    MsgBox("Automatic detection was attempted for the internal keyboard.`nIf it did not select the intended device, use the system tray menu to recalibrate it.", "Auto-detection", "4096")
}

; Always start the toggle monitor, regardless of current calibration state
StartAutoToggle()

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
    
    ; Temporarily listen to every detected keyboard device
    devList := AHI.GetDeviceList()
    for id, dev in devList {
        try AHI.SubscribeKeyboard(id, false, CalibrationCallback.Bind(id))
    }

    MsgBox("Please press ANY KEY on your BUILT-IN LAPTOP KEYBOARD to calibrate (you will only have to do this once).", "Keyboard Calibration", "4096")
}

CalibrationCallback(id, code, state) {
    global InternalKbdID, InternalKbdHandle, ConfigFile

    ; Ignore key releases
    if (!state) {
        return
    }
    
    ; Stop calibration listener
    devList := AHI.GetDeviceList()
    for currentId, dev in devList {
        try AHI.UnsubscribeKeyboard(currentId)
    }
    
    InternalKbdID := id
    InternalKbdHandle := devList[id].Handle
    
    ; Save hardware handle to config.ini
    IniWrite(InternalKbdHandle, ConfigFile, "Settings", "DeviceHandle")
    
    if WinExist("Keyboard Calibration ahk_class #32770") {
        WinClose("Keyboard Calibration ahk_class #32770")
        WinWaitClose("Keyboard Calibration ahk_class #32770", , 2)
    }
    
    MsgBox("Captured Laptop Keyboard Handle:`n" InternalKbdHandle "`n`nRecalibration is available in the system tray.", "Setup Complete", "4096")
    
    StartAutoToggle()
}

FindIDByHandle(targetHandle) {
    devList := AHI.GetDeviceList()
    for id, dev in devList {
        if (dev.Handle == targetHandle) {
            return id
        }
    }
    return 0
}

TryAutoDetectInternalKeyboard() {
    global InternalKbdID, InternalKbdHandle, ConfigFile

    devList := AHI.GetDeviceList()
    if (!IsObject(devList)) {
        return false
    }

    query := "SELECT * FROM Win32_Keyboard"
    kbdDevices := WMI.ExecQuery(query)
    for dev in kbdDevices {
        if (!IsLikelyInternalDevice(dev.PNPDeviceID)) {
            continue
        }

        targetHandle := FindHandleForWmiDevice(dev, devList)
        if (targetHandle != "") {
            InternalKbdID := FindIDByHandle(targetHandle)
            InternalKbdHandle := targetHandle
            IniWrite(InternalKbdHandle, ConfigFile, "Settings", "DeviceHandle")
            return true
        }
    }

    return false
}

FindHandleForWmiDevice(wmiDevice, devList) {
    if (!IsObject(wmiDevice) || !IsObject(devList)) {
        return ""
    }

    pnpId := wmiDevice.PNPDeviceID
    
    ; 1. MAPPING: Translate squashed WMI formats (MSFT0001) to expanded AHI formats (VEN_MSFT&DEV_0001)
    if (RegExMatch(pnpId, "(?i)(ACPI|HID)\\([A-Z]{4})([0-9A-Z]{4})", &match)) {
        targetVendor := match[2]
        targetDevice := match[3]
        for id, dev in devList {
            if InStr(dev.Handle, "VEN_" targetVendor) && InStr(dev.Handle, "DEV_" targetDevice) {
                return dev.Handle
            }
        }
    }

    ; 2. MAPPING: Standard USB VID/PID matching for external devices
    targetVid := 0
    targetPid := 0
    if (RegExMatch(pnpId, "i)VID_([0-9A-F]{4})", &vidMatch)) {
        targetVid := Integer("0x" vidMatch[1])
    }
    if (RegExMatch(pnpId, "i)PID_([0-9A-F]{4})", &pidMatch)) {
        targetPid := Integer("0x" pidMatch[1])
    }

    if (targetVid != 0) {
        for id, dev in devList {
            if (targetPid != 0 && dev.VID == targetVid && dev.PID == targetPid) {
                return dev.Handle
            }
            if (targetPid == 0 && dev.VID == targetVid) {
                return dev.Handle
            }
        }
    }

    ; 3. FALLBACK: Direct substring match
    for id, dev in devList {
        if (InStr(dev.Handle, pnpId) || InStr(pnpId, dev.Handle)) {
            return dev.Handle
        }
    }

    return ""
}

IsLikelyInternalDevice(pnpDeviceID) {
    if (!pnpDeviceID) {
        return false
    }
    return InStr(pnpDeviceID, "ACPI\") || InStr(pnpDeviceID, "PNP") || InStr(pnpDeviceID, "MSFT")
}

; ==========================================
; STARTUP TASK LOGIC
; ==========================================
RunHidden(cmd) {
    return RunWait('"' A_ComSpec '" /c ' . cmd, "", "Hide")
}

IsStartupTaskPresent() {
    taskName := "\AutoToggleInternalKeyboard"
    if RunHidden('schtasks /Query /TN "' . taskName . '" >nul 2>&1') != 0 {
        return false
    }

    currentPath := NormalizePath(A_ScriptFullPath)
    taskPath := GetStartupTaskPath(taskName)
    if (taskPath != "" && taskPath != currentPath) {
        UpdateStartupTaskPath(currentPath)
    }

    return true
}

GetStartupTaskPath(taskName) {
    DirCreate(A_Temp)
    taskXmlPath := A_Temp "\AutoToggleTask.xml"
    if FileExist(taskXmlPath) {
        FileDelete(taskXmlPath)
    }

    if RunHidden('schtasks /Query /TN "' . taskName . '" /XML > "' . taskXmlPath . '" 2>nul') != 0 || !FileExist(taskXmlPath) {
        return ""
    }

    file := FileOpen(taskXmlPath, "r")
    if (!file) {
        return ""
    }

    xmlText := StrReplace(file.Read(), "`r", "")
    file.Close()
    if FileExist(taskXmlPath) {
        FileDelete(taskXmlPath)
    }
    return NormalizePath(ExtractXmlValue(xmlText, "Command"))
}

ExtractXmlValue(xml, tag) {
    regex := "s)(?i)<" . tag . ">\s*(.*?)\s*</" . tag . ">"
    output := ""
    if RegExMatch(xml, regex, &output) {
        return Trim(output[1])
    }
    return ""
}

NormalizePath(path) {
    path := Trim(path)
    if (SubStr(path, 1, 1) == Chr(34) && SubStr(path, StrLen(path), 1) == Chr(34)) {
        path := SubStr(path, 2, StrLen(path) - 2)
    }
    return StrLower(StrReplace(path, "/", "\\"))
}

UpdateStartupTaskPath(newPath) {
    DeleteStartupTask()
    return RunHidden('schtasks /Create /TN "\AutoToggleInternalKeyboard" /TR "' . NormalizePath(newPath) . '" /SC ONLOGON /RL HIGHEST /F >nul 2>&1') == 0
}

CreateStartupTask() {
    return RunHidden('schtasks /Create /TN "\AutoToggleInternalKeyboard" /TR "' . A_ScriptFullPath . '" /SC ONLOGON /RL HIGHEST /F >nul 2>&1') == 0
}

DeleteStartupTask() {
    return RunHidden('schtasks /Delete /TN "\AutoToggleInternalKeyboard" /F >nul 2>&1') == 0
}

; ==========================================
; AUTO-TOGGLE MONITORING LOGIC
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

WMIEvent_OnObjectReady(params*) {
    CheckDevices()
}

CheckDevices() {
    global isBlocked, InternalKbdID, InternalKbdHandle, KeepInternalKeyboardEnabled
    
    if (InternalKbdID == 0 || AHI.GetDeviceList()[InternalKbdID].Handle != InternalKbdHandle) {
        InternalKbdID := FindIDByHandle(InternalKbdHandle)
    }

    externalKeyboardConnected := false
    devList := AHI.GetDeviceList()

    if (InternalKbdID != 0) {
        query := "SELECT * FROM Win32_Keyboard"
        kbdDevices := WMI.ExecQuery(query)
        for dev in kbdDevices {
            mappedHandle := FindHandleForWmiDevice(dev, devList)
            
            if (mappedHandle == InternalKbdHandle) {
                continue
            }
            if (InStr(dev.PNPDeviceID, "ACPI\") && mappedHandle == "") {
                continue
            }
            
            externalKeyboardConnected := true
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
}

ShowOSD(Message) {
    global ShowNotifications
    if (!ShowNotifications) {
        return
    }
    ToolTip(Message)
    SetTimer(() => ToolTip(), -2500)
}