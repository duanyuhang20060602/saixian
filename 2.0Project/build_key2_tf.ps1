param([string]$TdRoot = 'D:/TD', [int]$PlaceSeed = 3, [switch]$UseStaticBusEco, [string]$Python = '',
      [ValidateSet('read_design','opt_place','opt_route')][string]$StartStep = 'read_design')
$ErrorActionPreference = 'Stop'
$env:SAIXIAN_TD_ROOT = $TdRoot.Replace('\','/')
$env:SAIXIAN_PLACE_SEED = [string]$PlaceSeed
$env:SAIXIAN_START_STEP = $StartStep
$tdPrompt = Join-Path $TdRoot 'bin/td_commands_prompt.exe'
$outputName = 'SAIXIAN_KEY2_TF_20261010'
$started = Get-Date
$sourceSnapshot = @{}
if (!$Python) {
    $installedPython = Join-Path $env:LOCALAPPDATA 'Programs/Python/Python314/python.exe'
    $Python = if (Test-Path -LiteralPath $installedPython) { $installedPython } else { 'python' }
}
if ($UseStaticBusEco) {
    if ($PlaceSeed -ne 3 -or $StartStep -ne 'read_design') { throw 'Static bus ECO uses the frozen seed-3 baseline; omit PlaceSeed and StartStep' }
    & $Python (Join-Path $PSScriptRoot 'tests/verify_static_eco.py') --sources-only
    if ($LASTEXITCODE -ne 0) { throw 'Frozen baseline/source audit failed' }
}
foreach ($source in Get-ChildItem (Join-Path $PSScriptRoot 'src/user_source') -Recurse -File) {
    if ($source.Extension -in @('.v','.vh','.mif','.sdc','.adc','.cwc','.ipc','.tcl','.hex')) {
        $sourceSnapshot[$source.FullName] = (Get-FileHash -LiteralPath $source.FullName -Algorithm SHA256).Hash
    }
}
foreach ($name in @('SAIXIAN_KEY2_TF_20261010.al','build_saixian.tcl','key2_tf_flow.tcl','build_static_bus_eco.tcl')) {
    $path = Join-Path $PSScriptRoot ('src/td_project/' + $name)
    $sourceSnapshot[$path] = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
}
if ($UseStaticBusEco) {
    foreach ($source in Get-ChildItem (Join-Path $PSScriptRoot 'src/td_project/static_bus_baseline') -File) {
        $sourceSnapshot[$source.FullName] = (Get-FileHash -LiteralPath $source.FullName -Algorithm SHA256).Hash
    }
    $auditPath = Join-Path $PSScriptRoot 'tests/verify_static_eco.py'
    $sourceSnapshot[$auditPath] = (Get-FileHash -LiteralPath $auditPath -Algorithm SHA256).Hash
}
Push-Location (Join-Path $PSScriptRoot 'src/td_project')
try {
    if ($StartStep -in @('opt_place','opt_route')) {
        $checkpointSuffix = if ($StartStep -eq 'opt_place') { '_gate.db' } else { '_place.db' }
        $gateDb = Get-Item -LiteralPath ($outputName + $checkpointSuffix)
        foreach ($source in Get-ChildItem '../user_source' -Recurse -File) {
            if ($source.Extension -in @('.v','.vh','.mif','.sdc','.adc') -and $source.LastWriteTime -gt $gateDb.LastWriteTime) {
                throw "Source newer than gate database; use StartStep read_design: $($source.FullName)"
            }
        }
    }
    $nativeScript = if ($UseStaticBusEco) { 'build_static_bus_eco.tcl' } else { 'build_saixian.tcl' }
    & $tdPrompt $nativeScript *> 'key2_tf_build.log'
    if ($LASTEXITCODE -ne 0) { throw "TD failed: $LASTEXITCODE" }
    $log = Get-Content 'key2_tf_build.log' -Raw
    if ($log -match '(?m)^\S+ ERROR:') { throw 'TD reported a design/build error' }
    $timingFile = $outputName + '_pr.timing'
    $areaFile = $outputName + '_phy.area'
    $bitFile = $outputName + '.bit'
    foreach ($path in @($timingFile,$areaFile,$bitFile)) {
        if (!(Test-Path -LiteralPath $path) -or (Get-Item -LiteralPath $path).LastWriteTime -lt $started) {
            throw "Fresh output missing: $path"
        }
    }
    $timing = Get-Content $timingFile -Raw
    $setup = [regex]::Match($timing,'SWNS:\s*([-\d.]+)ns,\s*STNS:\s*([-\d.]+)ns')
    $hold = [regex]::Match($timing,'HWNS:\s*([-\d.]+)ns,\s*HTNS:\s*([-\d.]+)ns')
    $culture = [Globalization.CultureInfo]::InvariantCulture
    if (!$setup.Success -or !$hold.Success) { throw 'Timing summary missing' }
    $swns = [double]::Parse($setup.Groups[1].Value,$culture)
    $stns = [double]::Parse($setup.Groups[2].Value,$culture)
    $hwns = [double]::Parse($hold.Groups[1].Value,$culture)
    $htns = [double]::Parse($hold.Groups[2].Value,$culture)
    if ($swns -lt 0 -or $hwns -lt 0 -or $stns -ne 0 -or $htns -ne 0) { throw 'Routed timing failed; bit is not released' }
    $area = Get-Content $areaFile -Raw
    foreach ($resource in @('lut','reg','bram','bram32k','dsp')) {
        $match = [regex]::Match($area,"(?m)^#$resource\s+(\d+)\s+out of\s+(\d+)")
        if (!$match.Success -or [int]$match.Groups[1].Value -gt [int]$match.Groups[2].Value) {
            throw "Device capacity exceeded: $resource"
        }
    }
    foreach ($path in $sourceSnapshot.Keys) {
        if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $sourceSnapshot[$path]) {
            throw "Source changed during build; bit is not released: $path"
        }
    }
    if ($UseStaticBusEco) {
        & $Python (Join-Path $PSScriptRoot 'tests/verify_static_eco.py')
        if ($LASTEXITCODE -ne 0) { throw 'Implemented ECO/source equivalence audit failed; bit is not released' }
    }
    $release = Join-Path $PSScriptRoot 'releases/key2_tf_static_fix_20261011'
    New-Item -ItemType Directory -Force -Path $release | Out-Null
    Copy-Item -LiteralPath $bitFile -Destination $release -Force
    Copy-Item -LiteralPath $timingFile -Destination (Join-Path $release 'routed_timing.rpt') -Force
    Copy-Item -LiteralPath $areaFile -Destination (Join-Path $release 'resource.rpt') -Force
    Write-Host "PASS routed timing: setup $swns ns, hold $hwns ns"
} finally {
    $savedLog = Join-Path $PSScriptRoot ('validation/key2_tf_20261010/td_seed_' + $PlaceSeed + '.log')
    if (Test-Path -LiteralPath 'key2_tf_build.log') {
        Copy-Item -LiteralPath 'key2_tf_build.log' -Destination $savedLog -Force
    }
    Pop-Location
}
