param(
 [ValidateSet('A','B','Both')][string]$Board='Both',
 [string]$Python='',
 [string]$WorkDir='',
 [string]$TdRoot='',
 [switch]$VerifyOnly
)
$ErrorActionPreference='Stop'
$env:PYTHONDONTWRITEBYTECODE='1'
if(!$WorkDir){$WorkDir=Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) ('v54-merged-build-'+(Get-Date -Format 'yyyyMMdd_HHmmss'))}
$env:SAIXIAN_TEMP_ROOT=Join-Path $WorkDir 'temp'
$env:TEMP=$env:SAIXIAN_TEMP_ROOT
$env:TMP=$env:TEMP
New-Item -ItemType Directory -Force -Path $env:TEMP | Out-Null
if(!$Python){
 $runtime='C:/Users/39742/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe'
 if(Test-Path -LiteralPath $runtime){$Python=$runtime}
 else {$Python=(Get-Command python -ErrorAction Stop).Source}
}
$buildArgs=@('-B',(Join-Path $PSScriptRoot 'tools/build_saved_project.py'),'--board',$Board.ToLowerInvariant())
if($WorkDir){$buildArgs+=@('--work',$WorkDir)}
if($TdRoot){$buildArgs+=@('--td-root',$TdRoot)}
if($VerifyOnly){$buildArgs+='--verify-only'}
& $Python @buildArgs
if($LASTEXITCODE -ne 0){throw '5.4 project build or verification failed; consult the specified WorkDir build logs.'}
