@echo off
setlocal EnableDelayedExpansion
set "INPUT="
set "OUTPUT="

:parse
if "%~1"=="" goto doneparse
if /I "%~1"=="--input" (
  set "INPUT=%~2"
  shift
  shift
  goto parse
)
if /I "%~1"=="--output" (
  set "OUTPUT=%~2"
  shift
  shift
  goto parse
)
shift
goto parse

:doneparse
if not defined INPUT exit /b 2
if not defined OUTPUT exit /b 3

findstr /C:"BUG: returns input unchanged" "%INPUT%" >nul
if %ERRORLEVEL%==0 (
  > "%OUTPUT%" echo [LOGIC] Function does not sort and deduplicate.
  >> "%OUTPUT%" echo Recommendation: return sorted(set^(items^)^).
) else (
  > "%OUTPUT%" echo OK
)
exit /b 0
