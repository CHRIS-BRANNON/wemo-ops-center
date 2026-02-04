@echo off
SETLOCAL EnableDelayedExpansion

:: --- CONFIGURATION ---
SET "APP_NAME=WemoOps"
SET "SERVICE_NAME=wemo_service"
SET "PYTHON_CMD=python"
SET "ICON_FILE=icon.ico"

echo ========================================================
echo       WEMO OPS - MASTER BUILDER (WINDOWS)
echo ========================================================

:: 1. CHECK PYTHON
%PYTHON_CMD% --version >nul 2>&1
IF %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Python is not installed or not in your PATH.
    pause
    exit /b 1
)

:: 2. SETUP VIRTUAL ENVIRONMENT
echo [1/5] Setting up Build Environment...
if exist ".venv" (
    echo    - Cleaning old environment...
    rmdir /s /q .venv
)
%PYTHON_CMD% -m venv .venv

:: 3. INSTALL DEPENDENCIES
echo [2/5] Installing Libraries...
call .venv\Scripts\activate.bat
pip install --upgrade pip
pip install "pywemo>=2.1.1" customtkinter requests pyinstaller pyperclip

:: 4. BUILD EXECUTABLES
echo [3/5] Compiling Binaries...

if exist "build" rmdir /s /q build
if exist "dist" rmdir /s /q dist

:: Check for Icon
SET "ICON_FLAG="
SET "ADD_DATA_FLAG="
if exist "%ICON_FILE%" (
    echo    - Found Custom Icon: %ICON_FILE%
    SET "ICON_FLAG=--icon=%ICON_FILE%"
    :: This flag ensures the icon.ico is bundled INSIDE the exe so the Python script can read it at runtime
    SET "ADD_DATA_FLAG=--add-data %ICON_FILE%;."
) else (
    echo    - WARNING: 'icon.ico' not found. Using default icon.
)

:: Build GUI App
echo    - Building GUI...
pyinstaller --noconfirm --noconsole --onefile ^
    --name "%APP_NAME%" ^
    %ICON_FLAG% ^
    %ADD_DATA_FLAG% ^
    --collect-all customtkinter ^
    --hidden-import pywemo ^
    --hidden-import pyperclip ^
    wemo_ops_universal.py

:: Build Background Service (Service doesn't need an icon usually, but we can add it if you want)
echo    - Building Service...
pyinstaller --noconfirm --noconsole --onefile ^
    --name "%SERVICE_NAME%" ^
    %ICON_FLAG% ^
    --hidden-import pywemo ^
    wemo_ops_universal.py

:: 5. ORGANIZE INSTALLER
echo [4/5] Creating Installer Package...
SET "INSTALLER_DIR=dist\WemoOps_Installer"
mkdir "%INSTALLER_DIR%"

copy "dist\%APP_NAME%.exe" "%INSTALLER_DIR%\" >nul
copy "dist\%SERVICE_NAME%.exe" "%INSTALLER_DIR%\" >nul

:: 6. GENERATE INSTALL SCRIPT
echo [5/5] Generating 'install.bat'...

(
echo @echo off
echo echo Installing Wemo Ops...
echo.
echo :: 1. Define Paths
echo SET "TARGET_DIR=%%APPDATA%%\WemoOps"
echo SET "STARTUP_DIR=%%APPDATA%%\Microsoft\Windows\Start Menu\Programs\Startup"
echo.
echo :: 2. Copy Files
echo if not exist "%%TARGET_DIR%%" mkdir "%%TARGET_DIR%%"
echo copy /Y "WemoOps.exe" "%%TARGET_DIR%%\"
echo copy /Y "wemo_service.exe" "%%TARGET_DIR%%\"
echo.
echo :: 3. Create Shortcuts
echo echo    - Creating Desktop Shortcut...
echo set "SCRIPT=%%TEMP%%\CreateShortcuts.ps1"
echo echo ^$ws = New-Object -ComObject WScript.Shell ^> "%%SCRIPT%%"
echo echo ^$s = ^$ws.CreateShortcut^("$env:USERPROFILE\Desktop\Wemo Ops.lnk"^) ^>> "%%SCRIPT%%"
echo echo ^$s.TargetPath = "%%TARGET_DIR%%\WemoOps.exe" ^>> "%%SCRIPT%%"
echo echo ^$s.Save^(^) ^>> "%%SCRIPT%%"
echo.
echo :: 4. Register Startup Service
echo echo    - Registering Startup Service...
echo echo ^$s2 = ^$ws.CreateShortcut^("%%STARTUP_DIR%%\WemoOps_Service.lnk"^) ^>> "%%SCRIPT%%"
echo echo ^$s2.TargetPath = "%%TARGET_DIR%%\wemo_service.exe" ^>> "%%SCRIPT%%"
echo echo ^$s2.Save^(^) ^>> "%%SCRIPT%%"
echo.
echo :: Run PowerShell
echo powershell -ExecutionPolicy Bypass -File "%%SCRIPT%%"
echo del "%%SCRIPT%%"
echo.
echo echo ==================================================
echo echo Success! Wemo Ops is installed.
echo echo ==================================================
echo pause
) > "%INSTALLER_DIR%\install.bat"

echo.
echo ========================================================
echo    BUILD COMPLETE!
echo    Installer Location: dist\WemoOps_Installer
echo ========================================================
pause