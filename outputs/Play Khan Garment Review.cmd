@echo off
set "GODOT=%~dp0..\work\godot-portable\Godot.exe"
start "" "%GODOT%" --path "%~dp0..\game" res://scenes/garment_review.tscn --log-file "%~dp0..\work\garment-review.log"
