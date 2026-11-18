@echo off
rem DynamicQr sender: drag images onto this file, or double-click it to choose images.
powershell -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0DynamicQrSender.ps1" %*
if errorlevel 1 pause
