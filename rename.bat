@echo off
setlocal enabledelayedexpansion

:: --- CONFIGURATION ---
set "PLACEHOLDER_NAME=godot_game_template"
:: ---------------------

echo ============================================
echo   Godot Project: Rename References
echo ============================================
echo.
echo This script will rename all occurrences of "%PLACEHOLDER_NAME%" 
echo to your new Project Name in this folder and all subfolders.
echo.

:: 1. Get Project Name
set /p "PROJECT_NAME=Enter your new Project Name: "
if "!PROJECT_NAME!"=="" (
    echo [ERROR] Project Name cannot be empty.
    pause
    exit /b 1
)

echo [INFO] Renaming references to "!PROJECT_NAME!"...

:: 2. Use PowerShell for robust find-and-replace in files AND folder renaming
powershell -Command "$p='!PROJECT_NAME!'; $old='%PLACEHOLDER_NAME%'; Get-ChildItem -Recurse -File -Exclude 'setup.bat','rename.bat' | ForEach-Object { (Get-Content $_.FullName -Raw) -replace $old, $p | Set-Content $_.FullName -NoNewline }; Get-ChildItem -Recurse -Directory | Where-Object { $_.Name -match $old } | Sort-Object FullName -Descending | ForEach-Object { Rename-Item $_.FullName ($_.Name -replace $old, $p) }"

echo.
set /p "CLEAN=Clear .godot cache folder? (y/n) [n]: "
if /i "!CLEAN!"=="y" (
    if exist ".godot" (
        echo [INFO] Removing .godot directory...
        rd /s /q ".godot"
    )
)

echo.
echo ============================================
echo   SUCCESS! References updated to "!PROJECT_NAME!".
echo   You can now delete this script.
echo ============================================
echo.
pause
