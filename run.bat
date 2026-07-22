@echo off
start /b powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0app.ps1"
