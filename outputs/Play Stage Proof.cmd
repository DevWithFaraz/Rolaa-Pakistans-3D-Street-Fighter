@echo off
set "GODOT=C:\Program Files\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe"
if not exist "%GODOT%" (
  echo Godot was not found at the installed location. Open the game project in Godot and press F5.
  pause
  exit /b 1
)
start "" "%GODOT%" --path "%~dp0..\game"
