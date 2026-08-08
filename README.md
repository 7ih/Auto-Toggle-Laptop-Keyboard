# Auto-Toggle Laptop Keyboard
Instantly disables the laptop's built-in keyboard when an external keyboard is connected. Instantly re-enables it when the external keyboard is disconnected. No restart needed.

IMPORTANT: This program installs a third party driver for the keyboard, which may affect other programs. You can always uninstall. Works with Vanguard and VAC; other anti-cheats not tested.

## Installation
note: this setup is for 64 bit
1. [Download the repository](https://github.com/7ih/Auto-Toggle-Laptop-Keyboard/archive/refs/heads/main.zip) (feel free to delete the "src" folder if you're not a developer)
2. Run install.bat

When installing interception-driver-fix, enabling "lockdown driver permissions" is recommended.

## Usage
1. Run AutoKbdToggle.exe
2. Configure options as needed in the system tray (right click the program icon).

If you enable 'run on startup', and you move the .exe's location, you will have to rerun the .exe to fix the run on startup.

Delete config.ini to reset settings.

## Troubleshooting
1. Restart computer
2. Recalibrate internal keyboard
2. Check that the "Keep Internal Keyboard Enabled" option is off

This program may just not work on some laptops, sorry. Feel free to open a github issue.

## Build
1. Download AutoHotkey V2
2. In the AutoHotkey Dash app, select Compile and download Ahk2Exe
3. In Ahk2Exe, Select AutoToggleInternalKeyboard.ahk as source and compile

## Credits
Uses [AutoHotkey](https://github.com/autohotkey/autohotkey) (V2), [AutoHotInterception](https://github.com/evilC/AutoHotInterception), and [Interception](https://github.com/oblitum/Interception).

[interception-driver-fix](https://github.com/hygorostrowskij/interception-driver-fix) fixes external keyboards becoming unresponsive after replugging too many times.

[Keyboard icon created by Magnific - Flaticon](https://www.flaticon.com/free-icons/keyboard)
