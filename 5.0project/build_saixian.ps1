param(
 [ValidateSet('A','B','Both')][string]$Board='Both',
 [string]$Python='',
 [string]$WorkDir='',
 [string]$TdRoot='',
 [switch]$VerifyOnly
)
$ErrorActionPreference='Stop'
$env:PYTHONDONTWRITEBYTECODE='1'
$env:TEMP='E:/Codex/Temp/5.0project'
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
if($LASTEXITCODE -ne 0){throw '5.0 project build or verification failed; consult the E:/Codex/Work build logs.'}
