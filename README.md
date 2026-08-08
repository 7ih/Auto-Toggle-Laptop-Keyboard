# Auto-Toggle Laptop Keyboard
Disables the laptop's built-in keyboard when an external keyboard is connected. Re-enables when keyboard is disconnected.

Uses [AutoHotkey](https://github.com/autohotkey/autohotkey) (V2), [AutoHotInterception](https://github.com/evilC/AutoHotInterception), and [Interception](https://github.com/oblitum/Interception).

## Installation
note: this setup is for 64 bit
1. [Download the repository](https://github.com/7ih/Auto-Toggle-Laptop-Keyboard/archive/refs/heads/main.zip)
2. Run install.bat and follow the instructions

## Usage
1. Run AutoKbdToggle.exe
2. Configure options as needed in the system tray (right click the program in the system tray, up arrow in taskbar near clock).

If you enable run on startup, and you move the .exe's location, you will have to rerun the .exe to fix the run on startup.
Delete config.ini to reset settings.

## Troubleshooting
1. Restart computer
2. Recalibrate internal keyboard
2. Check that the "Keep Internal Keyboard Enabled" option is off
This program may just not work on some laptops, sorry.

## Build
1. Download AutoHotkey V2
2. In the AutoHotkey Dash app, select Compile and download Ahk2Exe
3. In Ahk2Exe, Select AutoToggleInternalKeyboard.ahk as source and compile

[interception-driver-fix](https://github.com/hygorostrowskij/interception-driver-fix) fixes external keyboard becoming unresponsive after repluggining too many times
<sub>[Keyboard icon created by Magnific - Flaticon](https://www.flaticon.com/free-icons/keyboard)</sub>