# ============================================================================
# run_accuracy_detached.ps1 : start scripts/run_accuracy.sh as a process that does NOT belong to this
# terminal / Claude session, so closing the window or the session does not stop the simulation.
# (The process is created through WMI, so its parent is the WMI service, not this shell.)
#
#   powershell -File scripts\run_accuracy_detached.ps1              (10,000 images, 500 per chunk)
#   powershell -File scripts\run_accuracy_detached.ps1 1000 250
#
# Finished chunks are skipped, so this also RESUMES an interrupted run.
# Progress : build\accuracy\progress.txt (one line per finished chunk)
# Finished : logs\accuracy_console.txt ends with a line "rc 0" (or "rc 1"), result in reports\accuracy_10k.txt
# It does not keep the PC awake: if Windows goes to sleep the run pauses and continues after wake-up.
# ============================================================================
param([int]$Total = 10000, [int]$Chunk = 500)

$rootWin = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$root = $rootWin -replace '\\', '/'

$busy = Get-CimInstance Win32_Process | Where-Object { @('xsim.exe', 'xsimk.exe', 'xelab.exe', 'xvlog.exe') -contains $_.Name }
if ($busy) {
    Write-Host "A simulation is already running (PID $($busy.ProcessId -join ', ')). Not starting a second one."
    exit 1
}

$bash = 'C:\Program Files\Git\bin\bash.exe'
if (-not (Test-Path $bash)) {
    $git = Get-Command git -ErrorAction SilentlyContinue
    if ($git) { $bash = Join-Path (Split-Path (Split-Path $git.Source)) 'bin\bash.exe' }
}
if (-not (Test-Path $bash)) { Write-Host "Git Bash (bash.exe) not found"; exit 1 }
$py = (Get-Command python -ErrorAction Stop).Source -replace '\\', '/'

New-Item -ItemType Directory -Force (Join-Path $rootWin 'logs') | Out-Null
$inner = "cd '$root' && PYTHON='$py' bash scripts/run_accuracy.sh $Total $Chunk > logs/accuracy_console.txt 2>&1; echo rc " + '$?' + " >> logs/accuracy_console.txt"
$cmd = '"' + $bash + '" -lc "' + $inner + '"'
$r = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{ CommandLine = $cmd; CurrentDirectory = $rootWin }
if ($r.ReturnValue -ne 0) { Write-Host "Could not start the process (WMI return value $($r.ReturnValue))"; exit 1 }
Write-Host "Started detached: PID $($r.ProcessId), $Total images in chunks of $Chunk"
Write-Host "Progress: build\accuracy\progress.txt   Finished when logs\accuracy_console.txt ends with 'rc 0'"
