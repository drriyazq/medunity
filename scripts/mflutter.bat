@echo off
REM Universal Flutter deploy: pull latest -> pub get -> run on phone.
REM Usage: mflutter [path]    (defaults to current directory)
REM Auto-detects branch and whether project is at root or app/ subdir.
REM
REM One-time setup:
REM   1. Copy this file to C:\mflutter.bat
REM   2. setx PATH "%%PATH%%;C:\"  (then reopen cmd)
REM   3. From any cmd window:  mflutter C:\medunity

setlocal

set "ROOT=%~1"
if "%ROOT%"=="" set "ROOT=%CD%"

cd /d "%ROOT%" || (echo Cannot cd to %ROOT% & exit /b 1)
if not exist .git (echo Not a git repo: %ROOT% & exit /b 1)

for /f "tokens=*" %%b in ('git rev-parse --abbrev-ref HEAD') do set "BRANCH=%%b"

echo === [%ROOT%] pulling origin/%BRANCH% ===
git pull origin %BRANCH% || exit /b 1

set "FLUTTER_DIR=%ROOT%"
if not exist "%FLUTTER_DIR%\pubspec.yaml" (
    if exist "%ROOT%\app\pubspec.yaml" (
        set "FLUTTER_DIR=%ROOT%\app"
    ) else (
        echo No pubspec.yaml found at %ROOT% or %ROOT%\app
        exit /b 1
    )
)

echo === flutter pub get in %FLUTTER_DIR% ===
cd /d "%FLUTTER_DIR%"
call flutter pub get || exit /b 1

echo === flutter run --uninstall-first ===
call flutter run --uninstall-first

endlocal
