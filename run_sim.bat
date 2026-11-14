@echo off
REM ============================================================
REM  run_sim.bat : double-click to run Vivado batch simulation
REM  result -> result.txt , logs -> logs\
REM ============================================================
cd /d "%~dp0"
set "VIV="
for %%P in (
  "C:\AMDDesignTools\2024.2\Vivado\bin\vivado.bat"
  "C:\Xilinx\Vivado\2024.2\bin\vivado.bat"
  "C:\Xilinx\2024.2\Vivado\bin\vivado.bat"
  "D:\Xilinx\Vivado\2024.2\bin\vivado.bat"
  "D:\AMDDesignTools\2024.2\Vivado\bin\vivado.bat"
) do if exist %%P set "VIV=%%~P"
if not defined VIV for /f "delims=" %%W in ('where vivado.bat 2^>nul') do set "VIV=%%W"
if not defined VIV (
  echo [ERROR] vivado.bat not found.
  echo Open this file with Notepad and add your Vivado path to the list above.
  pause
  exit /b 1
)
echo Using: %VIV%
echo This takes about 5-20 minutes. Please wait...
call "%VIV%" -mode batch -source run_sim.tcl -log run_sim.log -journal run_sim.jou -notrace
echo.
echo ===================== result.txt =====================
type result.txt
echo ======================================================
pause
