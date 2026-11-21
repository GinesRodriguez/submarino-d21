@echo off
rem Doble clic: abre la v21.16 en local. Para otra version: probar_local.cmd index.html
set ARCH=%1
if "%ARCH%"=="" set ARCH=Tu_Submarino_d21_v21_16.html
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0probar_local.ps1" -Archivo "%ARCH%"
echo.
echo Logs en: %~dp0logs
pause
