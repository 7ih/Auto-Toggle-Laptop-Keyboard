@echo off
:: Self-elevate the script to Administrator
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo Requesting Administrator privileges...
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

:: CRITICAL: Set working directory back to the script's folder after elevation
cd /d "%~dp0"

echo ===================================================
echo   Installing Auto Keyboard Toggle Tool
echo ===================================================
echo.

set "driverInstalled=0"
set "driverAlreadyInstalled=0"

:: 1. Install Interception Driver
echo [1/2] Installing Interception kernel driver...
set "keyboardDriver=%SystemRoot%\System32\drivers\keyboard.sys"

if exist "CommandLineInstaller\install-interception.exe" (
    if exist "%keyboardDriver%" (
        echo Interception driver files already present.
        set "driverAlreadyInstalled=1"
    ) else (
        "CommandLineInstaller\install-interception.exe" /install
        start /wait "" "CommandLineInstaller\interception-driver-fix-v0.5.2-x64-windows-static-release.exe"
        set "driverInstalled=1"
    )
) else (
    echo WARNING: Interception driver installer not found in CommandLineInstaller folder.
)

echo.

:: 2. Create Task Scheduler Entry
echo [2/2] Creating Task Scheduler entry...
schtasks /Query /TN "AutoToggleInternalKeyboard" >nul 2>&1
if errorlevel 1 (
    choice /M "Do you want AutoKbdToggle.exe to run automatically on log on?"
    if errorlevel 2 (
        echo Skipping automatic run on logon.
    ) else (
        schtasks /Create /TN "AutoToggleInternalKeyboard" /TR "\"%~dp0AutoKbdToggle.exe\"" /SC ONLOGON /RL HIGHEST /F
    )
) else (
    echo Task Scheduler entry already exists.
)

if "%driverAlreadyInstalled%" == "1" (
    echo.
    echo Running AutoKbdToggle.exe now...
    start "" "AutoKbdToggle.exe"
)

echo.
echo ===================================================
echo Installation Complete!
if "%driverInstalled%" == "1" (
    echo Please REBOOT your computer for the driver to load.
)
echo ===================================================
pause