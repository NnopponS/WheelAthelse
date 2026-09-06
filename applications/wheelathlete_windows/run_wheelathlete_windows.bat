@echo off
setlocal
cd /d "%~dp0"

python -c "import PySide6, bleak" >nul 2>nul
if errorlevel 1 (
  echo WheelAthlete Python PC dependencies are missing.
  echo Installing: tools\pc_gui\requirements.txt
  python -m pip install -r tools\pc_gui\requirements.txt
  if errorlevel 1 (
    echo.
    echo Dependency installation failed. Run:
    echo   python -m pip install -r tools\pc_gui\requirements.txt
    pause
    exit /b 1
  )
)

python -m tools.pc_gui %*
endlocal
