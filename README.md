# Auto-Toggle Laptop Keyboard
Disables the laptop's built-in keyboard when an external keyboard is connected. Re-enables when keyboard is disconnected.

Also does the same thing with the trackpad if wanted.

Uses [AutoHotkey](https://github.com/autohotkey/autohotkey) (V2), [AutoHotInterception](https://github.com/evilC/AutoHotInterception), and [Interception](https://github.com/oblitum/Interception).

## Installation
note: this setup is for 64 bit
1. Download [the repository](https://github.com/7ih/Auto-Toggle-Laptop-Keyboard/archive/refs/heads/main.zip)
2. Run install.bat and follow the instructions

## Usage
1. Run AutoKbdToggle.exe
2. Configure options as needed in the system tray.

The app attempts to find the built-in keyboard and trackpad. If it doesn't work, please right click the app in the system tray and select the recalibration option.

If you enable run on startup, and you move the .exe's location, you will have to rerun the .exe to fix the run on startup.

## Troubleshooting
1. Restart computer
2. Check that the "Keep Internal Keyboard Enabled" option is off
This program may just not work on some laptops, sorry.

## Build
1. Download AutoHotkey V2
2. In the AutoHotkey Dash app, select Compile and download Ahk2Exe
3. In Ahk2Exe, Select AutoToggleInternalKeyboard.ahk as source and compile

<sub>[Keyboard icon created by Magnific - Flaticon](https://www.flaticon.com/free-icons/keyboard)</sub>