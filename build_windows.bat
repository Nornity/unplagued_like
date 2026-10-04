@echo off
setlocal
set GODOT=godot
if exist "%~dp0godot.exe" set GODOT=%~dp0godot.exe
if not exist "%~dp0release" mkdir "%~dp0release"
"%GODOT%" --headless --path "%~dp0" --editor --quit
if errorlevel 1 exit /b %errorlevel%
"%GODOT%" --headless --path "%~dp0" --export-release "Windows Desktop" "%~dp0release\TheLastBell.exe"
if errorlevel 1 exit /b %errorlevel%
echo.
echo Built: %~dp0release\TheLastBell.exe
pause
