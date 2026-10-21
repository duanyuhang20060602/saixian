param([string]$TdRoot='D:/TD',[int]$PlaceSeed=3,
      [ValidateSet('read_design','opt_place')][string]$StartStep='read_design')
$ErrorActionPreference='Stop'
$tdDir=Join-Path $PSScriptRoot 'project/src/td_project'
$release=Join-Path $PSScriptRoot 'delivery'
$started=Get-Date
$sourceHashes=@{}
foreach($source in Get-ChildItem (Join-Path $PSScriptRoot 'project/src/user_source') -File -Recurse){
    $sourceHashes[$source.FullName]=(Get-FileHash -LiteralPath $source.FullName -Algorithm SHA256).Hash
}
$env:SAIXIAN_TD_ROOT=$TdRoot.Replace('\','/')
$env:SAIXIAN_PLACE_SEED=[string]$PlaceSeed
$env:SAIXIAN_START_STEP=$StartStep
foreach($name in @('SAIXIAN_PITCH_EXPERIMENT.al','build_pitch.tcl','key2_tf_flow.tcl')){
    $config=Join-Path $tdDir $name
    $sourceHashes[$config]=(Get-FileHash -LiteralPath $config -Algorithm SHA256).Hash
}
if($StartStep -eq 'opt_place'){
    $gate=Get-Item -LiteralPath (Join-Path $tdDir 'SAIXIAN_PITCH_EXPERIMENT_gate.db')
    foreach($source in Get-ChildItem (Join-Path $PSScriptRoot 'project/src/user_source') -File -Recurse){
        if($source.LastWriteTime -gt $gate.LastWriteTime){throw "Source newer than synthesis checkpoint: $($source.FullName)"}
    }
}
Push-Location $tdDir
try{
    & (Join-Path $TdRoot 'bin/td_commands_prompt.exe') 'build_pitch.tcl' *> 'td_build.log'
    $log=Get-Content -LiteralPath 'td_build.log' -Raw
    if($LASTEXITCODE -ne 0 -or $log -match '(?m)^\S+ ERROR:'){throw 'TD failed; inspect td_build.log'}
    foreach($suffix in @('.bit','_pr.timing','_phy.area')){
        $file=Get-Item -LiteralPath ('SAIXIAN_PITCH_EXPERIMENT'+$suffix)
        if($file.LastWriteTime -lt $started){throw "Stale artifact: $($file.Name)"}
    }
    $timing=Get-Content -LiteralPath 'SAIXIAN_PITCH_EXPERIMENT_pr.timing' -Raw
    $numberCulture=[Globalization.CultureInfo]::InvariantCulture
    foreach($key in @('SWNS','STNS','HWNS','HTNS')){
        $m=[regex]::Match($timing,"${key}:\s*([-\d.]+)ns")
        if(-not $m.Success){throw "Missing timing: $key"}
        if([double]::Parse($m.Groups[1].Value,$numberCulture) -lt 0){throw "Timing failed: $key"}
    }
    foreach($path in $sourceHashes.Keys){
        if((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $sourceHashes[$path]){throw "Source changed: $path"}
    }
    New-Item -ItemType Directory -Path $release -Force | Out-Null
    Copy-Item -LiteralPath 'SAIXIAN_PITCH_EXPERIMENT.bit','SAIXIAN_PITCH_EXPERIMENT_pr.timing','SAIXIAN_PITCH_EXPERIMENT_phy.area','td_build.log' -Destination $release -Force
    Write-Output "PASS build and routed timing. Delivery: $release"
}finally{Pop-Location}
