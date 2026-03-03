@echo off
setlocal enabledelayedexpansion

:: --- USER CONFIGURATION ---
set "DEFAULT_TEMPLATE_URL=https://github.com/brueningmax/godot_template.git"
set "PLACEHOLDER_NAME=godot_game_template"
:: --------------------------

echo ============================================
echo   Godot Project Template Setup
echo ============================================
echo.

:: 1. Get Project Name
set /p "PROJECT_NAME=Enter your new Project Name: "
if "!PROJECT_NAME!"=="" (
    echo [ERROR] Project Name cannot be empty.
    pause
    exit /b 1
)

:: 2. Get Template URL (Optional)
set /p "TEMPLATE_URL=Enter Template Git URL (Press Enter for default): "
if "!TEMPLATE_URL!"=="" set "TEMPLATE_URL=%DEFAULT_TEMPLATE_URL%"

echo.
echo [INFO] Initializing Git in current folder...
git init
if %errorlevel% neq 0 (
    echo [ERROR] Git init failed. Make sure Git is installed.
    pause
    exit /b 1
)

echo [INFO] Fetching template from !TEMPLATE_URL!...
:: We use 'pull' to bring files into the CURRENT folder instead of 'clone' into a subfolder
git remote add origin !TEMPLATE_URL!
git pull origin main --depth 1
if %errorlevel% neq 0 (
    echo [WARNING] Pull from 'main' failed, trying 'master'...
    git pull origin master --depth 1
)

if %errorlevel% neq 0 (
    echo [ERROR] Failed to fetch template. Please check the URL and your connection.
    pause
    exit /b 1
)

:: 3. Clean up Template Git History
echo [INFO] Cleaning up template Git history...
rd /s /q .git
git init
echo [INFO] Fresh Git repository initialized.

:: 4. Rename Project References
echo [INFO] Renaming references from "%PLACEHOLDER_NAME%" to "!PROJECT_NAME!"...
:: Using PowerShell one-liner for robust find-and-replace
powershell -Command "Get-ChildItem -Recurse -File -Exclude 'setup.bat' | ForEach-Object { (Get-Content $_.FullName -Raw) -replace '%PLACEHOLDER_NAME%', '!PROJECT_NAME!' | Set-Content $_.FullName -NoNewline }"

echo.
echo ============================================
echo   SUCCESS! Project "!PROJECT_NAME!" is ready.
echo ============================================
echo.
pause
