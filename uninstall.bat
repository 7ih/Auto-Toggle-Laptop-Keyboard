@echo off
:: Self-elevate the script to Administrator
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo Requesting Administrator privileges...
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

echo ===================================================
echo   Uninstalling Auto Keyboard Toggle Tool
echo ===================================================
echo.

:: 1. Terminate any running instances of the app
echo [1/3] Closing running instances...
taskkill /F /IM AutoKbdToggle.exe >nul 2>&1

:: 2. Delete Task Scheduler Entry
echo [2/3] Removing Task Scheduler entry...
schtasks /Query /TN "AutoToggleInternalKeyboard" >nul 2>&1
if errorlevel 1 (
    echo Task Scheduler entry not found.
) else (
    schtasks /Delete /TN "AutoToggleInternalKeyboard" /F >nul 2>&1
)

set "driverRemoved=0"

:: 3. Uninstall Interception Driver
echo [3/3] Uninstalling Interception kernel driver...
if exist "%~dp0CommandLineInstaller\install-interception.exe" (
    choice /M "Do you want to uninstall the Interception driver?"
    if errorlevel 2 (
        echo Skipping driver uninstall.
    ) else (
        "%~dp0CommandLineInstaller\install-interception.exe" /uninstall
        start /wait "" "C:\Program Files\Interception Driver Fix\unins000.exe"
        set "driverRemoved=1"
    )
) else (
    echo WARNING: Interception driver installer not found. Skipping driver uninstall.
)

:: 4. Clean up generated config file
if exist "%~dp0config.ini" (
    del /f /q "%~dp0config.ini" >nul 2>&1
)

echo.
echo ===================================================
echo Uninstallation Complete!
if "%driverRemoved%" == "1" (
    echo Please REBOOT your computer to complete driver removal.
)
echo ===================================================
pause