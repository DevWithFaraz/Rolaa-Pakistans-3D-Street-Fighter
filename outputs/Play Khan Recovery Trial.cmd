@echo off
set "GODOT=%~dp0..\work\godot-portable\Godot.exe"
start "" "%GODOT%" --path "%~dp0..\game" res://scenes/recovery_review.tscn --log-file "%~dp0..\work\recovery-manual-review.log"
