@echo off
REM Startet den Paket-Test ohne Ruecksicht auf die ExecutionPolicy der Maschine.
REM Argument 1: Ordner mit dem gebauten .nupkg (Default: C:\pkg)
set "SRC=%~1"
if "%SRC%"=="" set "SRC=C:\pkg"
powershell.exe -NoProfile -ExecutionPolicy Bypass -NoExit -File "%~dp0Test-Package.ps1" -Source "%SRC%"
