@echo off
setlocal
cd /d "%~dp0"

set APP_VERSION=1.7.0
set OUT_DIR=release
set WORK_DIR=build\pyinstaller

echo Building WheelAthlete %APP_VERSION% for Windows...
if exist "%OUT_DIR%" rmdir /s /q "%OUT_DIR%"
if exist "%WORK_DIR%" rmdir /s /q "%WORK_DIR%"

python -m PyInstaller --noconfirm --clean --windowed ^
  --name WheelAthlete ^
  --icon "%CD%\assets\wheelathlete-logo.ico" ^
  --distpath "%OUT_DIR%" --workpath "%WORK_DIR%\gui" --specpath "%WORK_DIR%\gui" ^
  --paths . ^
  tools\pc_gui\__main__.py
if errorlevel 1 exit /b 1

python -m PyInstaller --noconfirm --clean --console --onefile ^
  --name WheelAthleteDaemon ^
  --icon "%CD%\assets\wheelathlete-logo.ico" ^
  --distpath "%OUT_DIR%" --workpath "%WORK_DIR%\daemon" --specpath "%WORK_DIR%\daemon" ^
  --paths . ^
  --collect-submodules tools.pc_acquisition ^
  tools\pc_acquisition\daemon_entry.py
if errorlevel 1 exit /b 1

copy /y "%OUT_DIR%\WheelAthleteDaemon.exe" "%OUT_DIR%\WheelAthlete\_internal\WheelAthleteDaemon.exe" >nul
if errorlevel 1 exit /b 1
copy /y "tools\pc_gui\README.md" "%OUT_DIR%\WheelAthlete\README.txt" >nul
powershell -NoProfile -Command "Compress-Archive -Path '%OUT_DIR%\WheelAthlete' -DestinationPath '%OUT_DIR%\WheelAthlete-%APP_VERSION%-portable.zip' -Force"
if errorlevel 1 exit /b 1

set ISCC=%LOCALAPPDATA%\Programs\Inno Setup 6\ISCC.exe
if not exist "%ISCC%" (
  echo Inno Setup 6 not found: %ISCC%
  exit /b 1
)
"%ISCC%" installer.iss
if errorlevel 1 exit /b 1

echo.
echo Portable build created:
echo   %OUT_DIR%\WheelAthlete-%APP_VERSION%-portable.zip
echo   %OUT_DIR%\WheelAthleteSetup.exe
echo Extract it, then run WheelAthlete\WheelAthlete.exe. The daemon is bundled.
endlocal
