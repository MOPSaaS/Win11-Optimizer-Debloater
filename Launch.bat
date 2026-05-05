@echo off
:: Win11 Performance Optimizer (Safe Mode) - Self-elevating launcher
setlocal

net session >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    powershell -Command "Start-Process '%~dp0Launch.bat' -Verb RunAs"
    exit /b
)

cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0Win11Optimizer.ps1"
endlocal
