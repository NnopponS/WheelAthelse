@echo off
setlocal EnableExtensions

set "SCRIPT_DIR=%~dp0"
for %%I in ("%SCRIPT_DIR%..\..") do set "WINDOWS_APP_ROOT=%%~fI"
for %%I in ("%WINDOWS_APP_ROOT%\..\..") do set "REPO_ROOT=%%~fI"
cd /d "%WINDOWS_APP_ROOT%"

if not exist "%REPO_ROOT%\VERSION" (
  echo ERROR: VERSION file not found at repository root: %REPO_ROOT%\VERSION
  exit /b 1
)
set /p APP_VERSION=<"%REPO_ROOT%\VERSION"
set "OUT_DIR=release"
set "WORK_DIR=build\pyinstaller"

echo Building WheelAthlete %APP_VERSION% for Windows...
echo Windows application root: %WINDOWS_APP_ROOT%
echo Repository root: %REPO_ROOT%

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
  --add-data "%REPO_ROOT%\VERSION;." ^
  --exclude-module torch --exclude-module torchvision --exclude-module torchaudio ^
  --exclude-module tensorflow --exclude-module keras --exclude-module matplotlib ^
  --exclude-module numpy --exclude-module scipy --exclude-module yaml ^
  --distpath "%OUT_DIR%" --workpath "%WORK_DIR%\gui" --specpath "%WORK_DIR%\gui" ^
  --paths "%WINDOWS_APP_ROOT%" ^
  tools\pc_gui\__main__.py
if errorlevel 1 exit /b 1

python -m PyInstaller --noconfirm --clean --console --onefile ^
  --name WheelAthleteDaemon ^
  --icon "%REPO_ROOT%\assets\wheelathlete-logo.ico" ^
  --distpath "%OUT_DIR%" --workpath "%WORK_DIR%\daemon" --specpath "%WORK_DIR%\daemon" ^
  --paths "%WINDOWS_APP_ROOT%" ^
  --exclude-module torch --exclude-module torchvision --exclude-module torchaudio ^
  --exclude-module tensorflow --exclude-module keras --exclude-module matplotlib ^
  --exclude-module numpy --exclude-module scipy --exclude-module yaml ^
  --collect-submodules tools.pc_acquisition ^
  tools\pc_acquisition\daemon_entry.py
if errorlevel 1 exit /b 1

copy /y "%OUT_DIR%\WheelAthleteDaemon.exe" "%OUT_DIR%\WheelAthlete\_internal\WheelAthleteDaemon.exe" >nul
if errorlevel 1 exit /b 1
copy /y "tools\pc_gui\README.md" "%OUT_DIR%\WheelAthlete\README.txt" >nul

powershell -NoProfile -Command "Compress-Archive -Path '%OUT_DIR%\WheelAthlete' -DestinationPath '%OUT_DIR%\WheelAthlete-%APP_VERSION%-portable.zip' -Force"
if errorlevel 1 exit /b 1

set "ISCC="
where ISCC.exe >nul 2>nul
if not errorlevel 1 for /f "delims=" %%I in ('where ISCC.exe') do if not defined ISCC set "ISCC=%%I"
if not defined ISCC if exist "%LOCALAPPDATA%\Programs\Inno Setup 6\ISCC.exe" set "ISCC=%LOCALAPPDATA%\Programs\Inno Setup 6\ISCC.exe"
if not defined ISCC if exist "%ProgramFiles(x86)%\Inno Setup 6\ISCC.exe" set "ISCC=%ProgramFiles(x86)%\Inno Setup 6\ISCC.exe"
if not defined ISCC if exist "%ProgramFiles%\Inno Setup 6\ISCC.exe" set "ISCC=%ProgramFiles%\Inno Setup 6\ISCC.exe"
if not defined ISCC (
  echo ERROR: Inno Setup 6 was not found.
  echo Install Inno Setup 6, then run this script again.
  exit /b 1
)

"%ISCC%" /DMyAppVersion=%APP_VERSION% "%WINDOWS_APP_ROOT%\packaging\windows\installer.iss"
if errorlevel 1 exit /b 1

powershell -NoProfile -Command "$p='%OUT_DIR%\WheelAthleteSetup-%APP_VERSION%.exe'; $h=(Get-FileHash -Algorithm SHA256 $p).Hash.ToLowerInvariant(); $s=(Get-Item $p).Length; Write-Host ('Installer SHA256: ' + $h); Write-Host ('Installer bytes:  ' + $s)"

echo.
echo Windows artifacts created under %WINDOWS_APP_ROOT%\release:
echo   %OUT_DIR%\WheelAthlete-%APP_VERSION%-portable.zip
echo   %OUT_DIR%\WheelAthleteSetup-%APP_VERSION%.exe
echo.
echo The installer and portable package both bundle WheelAthleteDaemon.exe.
endlocal
