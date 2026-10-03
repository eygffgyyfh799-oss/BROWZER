@echo off
setlocal
chcp 65001 >nul
title AI Video Upscaler and Enhancer Pro
cd /d "%~dp0"

rem Started from inside the zip without extracting it?
if not exist "%~dp0enhancer\__main__.py" goto fail_not_extracted

set "PYEXE=%~dp0python\python.exe"
set "PYURL=https://github.com/astral-sh/python-build-standalone/releases/download/20251014/cpython-3.12.12+20251014-x86_64-pc-windows-msvc-install_only.tar.gz"
set "PYARC=%TEMP%\ai-video-enhancer-python.tar.gz"
set "CHECK=import sys;assert sys.version_info.major==3 and sys.version_info.minor>=9"

rem 1) Portable Python inside this folder (bundled or downloaded earlier).
if exist "%PYEXE%" goto run

rem 2) A Python already installed on this PC.
python -c "%CHECK%" >nul 2>nul && set "PYEXE=python" && goto run
py -3 -c "%CHECK%" >nul 2>nul && set "PYEXE=py" && goto run

rem 3) Download portable Python into this folder (no installer, no admin rights).
echo.
echo   Downloading portable Python (one time only, about 45 MB) ...
echo.
del "%PYARC%" >nul 2>nul
curl.exe -L --fail --retry 3 --progress-bar -o "%PYARC%" "%PYURL%"
if not exist "%PYARC%" powershell -NoProfile -ExecutionPolicy Bypass -Command "$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol='Tls12'; Invoke-WebRequest -UseBasicParsing -Uri $env:PYURL -OutFile $env:PYARC"
if not exist "%PYARC%" goto fail_download
echo   Extracting ...
tar -xzf "%PYARC%" -C "%~dp0."
del "%PYARC%" >nul 2>nul
if not exist "%PYEXE%" goto fail_extract
echo   Python ready.

:run
"%PYEXE%" -m enhancer %*
if errorlevel 1 pause
exit /b

:fail_not_extracted
echo.
echo   Please extract the zip file first:
echo   Right-click the zip, choose "Extract All...", then open the extracted folder
echo   and double-click run.bat again.
echo.
pause
exit /b 1

:fail_download
echo.
echo   Could not download Python.
echo   - Check your internet connection.
echo   - Your antivirus or firewall may be blocking the download.
echo   Then run this file again.
echo.
pause
exit /b 1

:fail_extract
echo.
echo   Could not extract Python into:
echo   %~dp0
echo   - Move this folder somewhere you can write to, e.g. Desktop or Documents
echo     (not "Program Files"), then run this file again.
echo.
pause
exit /b 1
