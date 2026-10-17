param([string]$Python='C:\Users\39742\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe',
      [string]$TdRoot='C:\Anlogic\TD_6.2.1_Engineer_6.2.168.116')
$ErrorActionPreference='Stop'
$env:TEMP='E:\Codex\Temp';$env:TMP=$env:TEMP
$waterRoot=Join-Path $PSScriptRoot 'water_single'
& $Python "$waterRoot\tools\prepare.py"
if($LASTEXITCODE -ne 0){throw 'Preparation failed'}
& $Python "$waterRoot\tools\verify.py" --full
if($LASTEXITCODE -ne 0){throw 'RTL tests failed'}
& $Python "$waterRoot\tools\verify_adapters.py"
if($LASTEXITCODE -ne 0){throw 'Video adapter tests failed'}
& $Python "$waterRoot\tools\release.py" --begin
if($LASTEXITCODE -ne 0){throw 'Cannot record build inputs'}
Push-Location "$waterRoot\project"
try {
    Remove-Item Env:WATER_ELAB_ONLY -ErrorAction SilentlyContinue
    & "$TdRoot\bin\td_commands_prompt.exe" ((Join-Path $waterRoot 'project/build.tcl') -replace '\\','/') *> "$waterRoot\validation\td_build.log"
    if($LASTEXITCODE -ne 0){throw 'TD build failed'}
    & "$TdRoot\bin\td_commands_prompt.exe" ((Join-Path $waterRoot 'project/audit.tcl') -replace '\\','/') *> "$waterRoot\validation\timing_audit.log"
    if($LASTEXITCODE -ne 0){throw 'TD timing audit failed'}
} finally {Pop-Location}
& $Python "$waterRoot\tools\release.py"
if($LASTEXITCODE -ne 0){throw 'Release refused: stale inputs, timing failure, or local clock route'}
