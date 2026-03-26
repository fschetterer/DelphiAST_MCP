@echo off
setlocal

:: ── Parameters ────────────────────────────────────────────────────────────────
set RTL=%1
if "%RTL%"=="" set RTL=23

set CONFIG=%2
if "%CONFIG%"=="" set CONFIG=Debug

set PLATFORM=%3
if "%PLATFORM%"=="" set PLATFORM=Win64

set SKIPCLEAN=%4
set SHOWWARNINGS=%5

:: ── rsvars ────────────────────────────────────────────────────────────────────
set _CONFIG=%CONFIG%
set _PLATFORM=%PLATFORM%
call "C:\Program Files (x86)\Embarcadero\Studio\%RTL%.0\bin\rsvars.bat"
if errorlevel 1 (echo rsvars.bat not found for RTL %RTL% & exit /b 1)
set CONFIG=%_CONFIG%
set PLATFORM=%_PLATFORM%

:: ── Console output ────────────────────────────────────────────────────────────
set CONSOLE=/nologo /v:q /clp:NoSummary;ErrorsOnly
if not "%SHOWWARNINGS%"=="" set CONSOLE=/nologo /v:m /clp:NoSummary

:: ── File log ──────────────────────────────────────────────────────────────────
if not exist "..\logs" mkdir "..\logs"
set LOGTO=/fl /flp:logfile=..\logs\DelphiAST_MCP.log;verbosity=normal

:: ── Clean + Build ─────────────────────────────────────────────────────────────
if "%SKIPCLEAN%"=="" (
    msbuild "DelphiAST_MCP.dproj" /nologo /v:q /t:clean
    if errorlevel 1 (echo Clean failed & exit /b 1)
)
msbuild "DelphiAST_MCP.dproj" %CONSOLE% %LOGTO% /p:Config=%CONFIG% /p:Platform=%PLATFORM% /t:Build
exit /b %errorlevel%
