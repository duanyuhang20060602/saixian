$ErrorActionPreference = 'Stop'
$taskPython = 'python'
$taskRoot = $PSScriptRoot
$taskTdRoot = if ($env:SAIXIAN_TD_ROOT) { $env:SAIXIAN_TD_ROOT } else { 'C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116' }
& $taskPython "$taskRoot/tools/configure_projects.py"
if ($LASTEXITCODE -ne 0) { throw 'Project configuration failed.' }
foreach ($taskRole in @('board_a', 'board_b')) {
    & $taskPython "$taskRoot/tools/release.py" snapshot $taskRole
    if ($LASTEXITCODE -ne 0) { throw "Source snapshot failed: $taskRole" }
    Push-Location "$taskRoot/projects/$taskRole/src/td_project"
    try {
        & "$taskTdRoot/bin/td_commands_prompt.exe" build_board.tcl *> build.log
        if ($LASTEXITCODE -ne 0) { throw "TD build failed: $taskRole" }
    } finally { Pop-Location }
    & $taskPython "$taskRoot/tools/release.py" collect $taskRole
    if ($LASTEXITCODE -ne 0) { throw "Timing/source validation failed: $taskRole" }
}
& $taskPython "$taskRoot/tools/validation.py"
if ($LASTEXITCODE -ne 0) { throw 'Required simulation evidence missing or failed. Run tools/run_tests.py.' }
& $taskPython "$taskRoot/tools/release.py" package
if ($LASTEXITCODE -ne 0) { throw 'Release packaging failed.' }
