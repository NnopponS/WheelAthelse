@echo off
setlocal EnableExtensions

set "SCRIPT_DIR=%~dp0"
for %%I in ("%SCRIPT_DIR%..\..") do set "REPO_ROOT=%%~fI"
cd /d "%REPO_ROOT%"

if not exist "VERSION" (
  echo ERROR: VERSION file not found at repository root.
  exit /b 1
)
set /p APP_VERSION=<VERSION
set "OUT_DIR=release"
set "WORK_DIR=build\pyinstaller"

echo Building WheelAthlete %APP_VERSION% for Windows...

python -c "import PyInstaller" >nul 2>nul
if errorlevel 1 (
  echo ERROR: PyInstaller is not installed.
  echo Install it with: python -m pip install pyinstaller
  exit /b 1
)

if exist "%OUT_DIR%" rmdir /s /q "%OUT_DIR%"
if exist "%WORK_DIR%" rmdir /s /q "%WORK_DIR%"

python -m PyInstaller --noconfirm --clean --windowed ^
  --name WheelAthlete ^
  --icon "%REPO_ROOT%\assets\wheelathlete-logo.ico" ^
  --distpath "%OUT_DIR%" --workpath "%WORK_DIR%\gui" --specpath "%WORK_DIR%\gui" ^
  --paths "%REPO_ROOT%" ^
  tools\pc_gui\__main__.py
if errorlevel 1 exit /b 1

python -m PyInstaller --noconfirm --clean --console --onefile ^
  --name WheelAthleteDaemon ^
  --icon "%REPO_ROOT%\assets\wheelathlete-logo.ico" ^
  --distpath "%OUT_DIR%" --workpath "%WORK_DIR%\daemon" --specpath "%WORK_DIR%\daemon" ^
  --paths "%REPO_ROOT%" ^
  --collect-submodules tools.pc_acquisition ^
  tools\pc_acquisition\daemon_entry.py
if errorlevel 1 exit /b 1

copy /y "%OUT_DIR%\WheelAthleteDaemon.exe" "%OUT_DIR%\WheelAthlete\_internal\WheelAthleteDaemon.exe" >nul
if errorlevel 1 exit /b 1
copy /y "tools\pc_gui\README.md" "%OUT_DIR%\WheelAthlete\README.txt" >nul

powershell -NoProfile -Command "Compress-Archive -Path '%OUT_DIR%\WheelAthlete' -DestinationPath '%OUT_DIR%\WheelAthlete-%APP_VERSION%-portable.zip' -Force"
if errorlevel 1 exit /b 1

set "ISCC=%LOCALAPPDATA%\Programs\Inno Setup 6\ISCC.exe"
if not exist "%ISCC%" (
  echo ERROR: Inno Setup 6 not found: %ISCC%
  echo Install Inno Setup 6, then run this script again.
  exit /b 1
)

"%ISCC%" /DMyAppVersion=%APP_VERSION% "packaging\windows\installer.iss"
if errorlevel 1 exit /b 1

echo.
echo Windows artifacts created:
echo   %OUT_DIR%\WheelAthlete-%APP_VERSION%-portable.zip
echo   %OUT_DIR%\WheelAthleteSetup-%APP_VERSION%.exe
echo.
echo The installer and portable package both bundle WheelAthleteDaemon.exe.
endlocal
