@echo off
setlocal EnableExtensions
cd /d "%~dp0"

set "VENV=%~dp0.venv"
set "PYTHON=%VENV%\Scripts\python.exe"

if not exist "%PYTHON%" (
  echo Preparing WheelAthlete Python 3.12 environment...
  where uv >nul 2>nul
  if not errorlevel 1 (
    uv venv "%VENV%" --python 3.12 --seed
  ) else (
    where py >nul 2>nul
    if errorlevel 1 (
      echo.
      echo WheelAthlete needs either uv or Python 3.12 on this PC.
      echo Install uv, then run this file again: https://docs.astral.sh/uv/
      pause
      exit /b 1
    )
    py -3.12 -m venv "%VENV%"
  )
  if errorlevel 1 goto :bootstrap_failed
)

"%PYTHON%" -c "import PySide6, bleak, numpy, scipy" >nul 2>nul
if errorlevel 1 (
  echo Installing WheelAthlete source dependencies...
  where uv >nul 2>nul
  if not errorlevel 1 (
    uv pip install --python "%PYTHON%" -r tools\pc_gui\requirements.txt -r tools\pc_gui\requirements-model.txt
  ) else (
    "%PYTHON%" -m pip install -r tools\pc_gui\requirements.txt -r tools\pc_gui\requirements-model.txt
  )
  if errorlevel 1 goto :bootstrap_failed
)

if not exist "%USERPROFILE%\Documents\WheelAthlete\PC Sessions" mkdir "%USERPROFILE%\Documents\WheelAthlete\PC Sessions" >nul
if not exist "%USERPROFILE%\Documents\WheelAthlete\Model" mkdir "%USERPROFILE%\Documents\WheelAthlete\Model" >nul
if not exist "%USERPROFILE%\Documents\WheelAthlete\Logs" mkdir "%USERPROFILE%\Documents\WheelAthlete\Logs" >nul

"%PYTHON%" -m tools.pc_gui %*
set "EXIT_CODE=%ERRORLEVEL%"
endlocal & exit /b %EXIT_CODE%

:bootstrap_failed
echo.
echo WheelAthlete source environment setup failed.
echo You can retry by running this .bat again.
pause
endlocal & exit /b 1
