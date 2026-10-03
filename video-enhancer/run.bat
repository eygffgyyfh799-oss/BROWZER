@echo off
chcp 65001 >nul
title AI Video Upscaler ^& Enhancer Pro
cd /d "%~dp0"

set "PY="
set "PYLOCAL=%LOCALAPPDATA%\Programs\Python\Python312\python.exe"
set "CHECK=import sys;assert sys.version_info.major==3 and sys.version_info.minor>=9"

python -c "%CHECK%" >nul 2>nul && set "PY=python"
if not defined PY py -3 -c "%CHECK%" >nul 2>nul && set "PY=py -3"
if not defined PY if exist "%PYLOCAL%" set PY="%PYLOCAL%"

if not defined PY (
  echo.
  echo   Python was not found - installing it automatically, please wait...
  echo.
  winget install -e --id Python.Python.3.12 --scope user --silent --accept-package-agreements --accept-source-agreements >nul 2>nul
  if exist "%PYLOCAL%" set PY="%PYLOCAL%"
)
if not defined PY (
  echo   Downloading Python installer from python.org ...
  powershell -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol='Tls12'; Invoke-WebRequest 'https://www.python.org/ftp/python/3.12.7/python-3.12.7-amd64.exe' -OutFile \"$env:TEMP\python-setup.exe\""
  "%TEMP%\python-setup.exe" /quiet InstallAllUsers=0 PrependPath=1 Include_test=0
  if exist "%PYLOCAL%" set PY="%PYLOCAL%"
)
if not defined PY (
  echo.
  echo   Could not install Python automatically.
  echo   Please install it from https://www.python.org/downloads/ and run this file again.
  pause
  exit /b 1
)

%PY% -m enhancer %*
if errorlevel 1 pause
