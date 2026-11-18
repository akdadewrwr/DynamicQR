@echo off
rem DynamicQr sender: drag images onto this file, or double-click it to choose images.
rem Explorer quotes dropped paths only when they contain spaces, so a name like a&b.png would break %*.
rem When launched via "cmd /c" (Explorer, double-click, PowerShell), the raw command line is handed to
rem PowerShell to split safely, and "exit" stops cmd from running any text after an unquoted "&".
setlocal DisableDelayedExpansion
set "DQR_PS1=%~dp0DynamicQrSender.ps1"
set "DQR_BAT=%~f0"
setlocal EnableDelayedExpansion
set "DQR_CMDLINE=!cmdcmdline!"
if /i "!DQR_CMDLINE:/c =!"=="!DQR_CMDLINE!" goto console
powershell -NoProfile -ExecutionPolicy Bypass -STA -File "!DQR_PS1!" -FromCmdLine
if errorlevel 1 pause
exit
:console
endlocal
powershell -NoProfile -ExecutionPolicy Bypass -STA -File "%DQR_PS1%" %*
if errorlevel 1 pause
