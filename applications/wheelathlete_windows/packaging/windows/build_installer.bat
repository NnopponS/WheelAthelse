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
  --add-data "%WINDOWS_APP_ROOT%\tools\pc_gui\biwheel3d_runtime\BiWheel3D-XY-Yaw-current_best.json;tools\pc_gui\biwheel3d_runtime" ^
  --add-data "%WINDOWS_APP_ROOT%\tools\pc_gui\biwheel3d_runtime\SOURCE.json;tools\pc_gui\biwheel3d_runtime" ^
  --add-data "%WINDOWS_APP_ROOT%\tools\pc_gui\biwheel3d_runtime\BIWHEEL3D_LICENSE.txt;tools\pc_gui\biwheel3d_runtime" ^
  --collect-submodules tools.pc_gui.biwheel3d_runtime ^
  --exclude-module torch --exclude-module torchvision --exclude-module torchaudio ^
  --exclude-module tensorflow --exclude-module keras --exclude-module matplotlib ^
  --exclude-module scipy --exclude-module yaml ^
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

copy /y "tools\pc_gui\README.md" "%OUT_DIR%\WheelAthlete\README.txt" >nul
if errorlevel 1 exit /b 1

if not exist "%REPO_ROOT%\applications\wheelathlete_mobile\assets\models\wheelathlete_biwheel3d_m4.onnx" (
  echo ERROR: Bundled BiWheel3D ONNX model was not found.
  exit /b 1
)
if not exist "%OUT_DIR%\WheelAthlete\Model" mkdir "%OUT_DIR%\WheelAthlete\Model"
copy /y "%REPO_ROOT%\applications\wheelathlete_mobile\assets\models\wheelathlete_biwheel3d_m4.onnx" "%OUT_DIR%\WheelAthlete\Model\wheelathlete_biwheel3d_m4.onnx" >nul
if errorlevel 1 exit /b 1
copy /y "%WINDOWS_APP_ROOT%\tools\pc_gui\biwheel3d_runtime\BiWheel3D-XY-Yaw-current_best.json" "%OUT_DIR%\WheelAthlete\Model\BiWheel3D-XY-Yaw-current_best.json" >nul
if errorlevel 1 exit /b 1
copy /y "%WINDOWS_APP_ROOT%\tools\pc_gui\biwheel3d_runtime\BIWHEEL3D_LICENSE.txt" "%OUT_DIR%\WheelAthlete\Model\BIWHEEL3D_LICENSE.txt" >nul
if errorlevel 1 exit /b 1

set "SIGNING_ENABLED=0"
if defined WHEELATHLETE_SIGN_CERT_SHA1 set "SIGNING_ENABLED=1"
if defined WHEELATHLETE_TIMESTAMP_URL set "SIGNING_ENABLED=1"
if defined WHEELATHLETE_SIGN_CERT_SUBJECT set "SIGNING_ENABLED=1"
if "%SIGNING_ENABLED%"=="1" if not defined WHEELATHLETE_SIGN_CERT_SHA1 (
  echo ERROR: WHEELATHLETE_SIGN_CERT_SHA1 is required when signing is enabled.
  exit /b 1
)
if "%SIGNING_ENABLED%"=="1" if not defined WHEELATHLETE_TIMESTAMP_URL (
  echo ERROR: WHEELATHLETE_TIMESTAMP_URL is required when signing is enabled.
  exit /b 1
)
if "%SIGNING_ENABLED%"=="1" if not defined WHEELATHLETE_SIGN_CERT_SUBJECT (
  echo ERROR: WHEELATHLETE_SIGN_CERT_SUBJECT is required when signing is enabled.
  exit /b 1
)
copy /y "%OUT_DIR%\WheelAthleteDaemon.exe" "%OUT_DIR%\WheelAthlete\_internal\WheelAthleteDaemon.exe" >nul
if errorlevel 1 exit /b 1
copy /y "%SCRIPT_DIR%stop_installed_daemon.ps1" "%OUT_DIR%\WheelAthlete\stop_installed_daemon.ps1" >nul
if errorlevel 1 exit /b 1

if "%SIGNING_ENABLED%"=="1" (
  powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%SCRIPT_DIR%sign_windows_tree.ps1" -Root "%OUT_DIR%\WheelAthlete" -CertificateThumbprint "%WHEELATHLETE_SIGN_CERT_SHA1%" -TimestampUrl "%WHEELATHLETE_TIMESTAMP_URL%" -ExpectedSubject "%WHEELATHLETE_SIGN_CERT_SUBJECT%"
  if errorlevel 1 exit /b 1
) else (
  echo WARNING: no signing identity supplied; artifacts are for local testing only.
)

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

set "INNO_SIGN_COMMAND=powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $q%SCRIPT_DIR%sign_windows_artifact.ps1$q -Path $f -CertificateThumbprint %WHEELATHLETE_SIGN_CERT_SHA1% -TimestampUrl $q%WHEELATHLETE_TIMESTAMP_URL%$q -ExpectedSubject $q%WHEELATHLETE_SIGN_CERT_SUBJECT%$q"
if "%SIGNING_ENABLED%"=="1" (
  "%ISCC%" /DMyAppVersion=%APP_VERSION% /DMySignedBuild=1 "/Swheelathlete=%INNO_SIGN_COMMAND%" "%WINDOWS_APP_ROOT%\packaging\windows\installer.iss"
) else (
  "%ISCC%" /DMyAppVersion=%APP_VERSION% "%WINDOWS_APP_ROOT%\packaging\windows\installer.iss"
)
if errorlevel 1 exit /b 1

powershell -NoProfile -Command "Compress-Archive -Path '%OUT_DIR%\WheelAthlete' -DestinationPath '%OUT_DIR%\WheelAthlete-%APP_VERSION%-portable.zip' -Force"
if errorlevel 1 exit /b 1

if "%SIGNING_ENABLED%"=="1" (
  powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%SCRIPT_DIR%write_release_metadata.ps1" -ReleaseDir "%WINDOWS_APP_ROOT%\%OUT_DIR%" -Version "%APP_VERSION%" -RequireValidSignatures -ExpectedSignerSubject "%WHEELATHLETE_SIGN_CERT_SUBJECT%"
) else (
  powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%SCRIPT_DIR%write_release_metadata.ps1" -ReleaseDir "%WINDOWS_APP_ROOT%\%OUT_DIR%" -Version "%APP_VERSION%"
)
if errorlevel 1 exit /b 1

echo.
echo Windows artifacts created under %WINDOWS_APP_ROOT%\release:
echo   %OUT_DIR%\WheelAthlete-%APP_VERSION%-portable.zip
echo   %OUT_DIR%\WheelAthleteSetup-%APP_VERSION%.exe
echo   %OUT_DIR%\signing-report.json
echo   %OUT_DIR%\SHA256SUMS.txt
echo.
echo The installer and portable package bundle WheelAthleteDaemon.exe and the default Model library.
endlocal
