@echo off
REM ============================================================
REM  run_sim.bat : double-click to run Vivado batch simulation
REM  run from the repository root (this file is in scripts\)
REM  result -> result.txt , logs -> logs\  (Vivado log: logs\run_sim.log)
REM  exit code: 0 = both testbenches PASS, 1 = FAIL
REM  extra arguments are passed to run_sim.tcl, e.g.  run_sim.bat 100 fresh
REM ============================================================
cd /d "%~dp0.."
set "VIV="
for %%P in (
  "E:\Xilinx\Vivado\2024.2\bin\vivado.bat"
  "C:\AMDDesignTools\2024.2\Vivado\bin\vivado.bat"
  "C:\Xilinx\Vivado\2024.2\bin\vivado.bat"
  "C:\Xilinx\2024.2\Vivado\bin\vivado.bat"
  "D:\Xilinx\Vivado\2024.2\bin\vivado.bat"
  "D:\AMDDesignTools\2024.2\Vivado\bin\vivado.bat"
) do if not defined VIV if exist %%P set "VIV=%%~P"
if not defined VIV for /f "delims=" %%W in ('where vivado.bat 2^>nul') do set "VIV=%%W"
if not defined VIV (
  echo [ERROR] vivado.bat not found.
  echo Open this file with Notepad and add your Vivado path to the list above.
  pause
  exit /b 1
)
if not exist logs mkdir logs
echo Using: %VIV%
echo This takes about 5-20 minutes. Please wait...
if "%~1"=="" (
  call "%VIV%" -mode batch -source scripts\run_sim.tcl -log logs\run_sim.log -journal logs\run_sim.jou -notrace
) else (
  call "%VIV%" -mode batch -source scripts\run_sim.tcl -log logs\run_sim.log -journal logs\run_sim.jou -notrace -tclargs %*
)
set "RC=%ERRORLEVEL%"
echo.
echo ===================== result.txt =====================
type result.txt
echo ======================================================
if "%RC%"=="0" (echo RESULT: PASS) else (echo RESULT: FAIL ^(exit code %RC%^))
if not defined RUN_SIM_NOPAUSE pause
exit /b %RC%
