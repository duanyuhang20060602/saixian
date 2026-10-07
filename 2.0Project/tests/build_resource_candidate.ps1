param([string]$WorkRoot='E:/Codex/Work/saixian_2_opt/build', [int]$Seed=12)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$work=Join-Path $WorkRoot (Get-Date -Format 'yyyyMMdd_HHmmss')
New-Item -ItemType Directory -Force -Path $work | Out-Null
Copy-Item -LiteralPath (Join-Path $root 'src') -Destination $work -Recurse
$tdProject=Join-Path $work 'src/td_project'
$project=Join-Path $tdProject 'HDMI1.4b_Transmitter_v2.0.al'
$text=Get-Content -LiteralPath $project -Raw
$text=[regex]::Replace($text,'(<Project[^>]* Path=")[^"]+','$1'+$tdProject.Replace('\','/'))
Set-Content -LiteralPath $project -Value $text -Encoding utf8
Push-Location $tdProject
try {
    foreach($flag in Get-ChildItem -LiteralPath $tdProject -Filter '.*.error.f'){
        Remove-Item -LiteralPath $flag.FullName
    }
    $env:SAIXIAN_PLACE_SEED=[string]$Seed
    & 'C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/bin/td_commands_prompt.exe' build_saixian.tcl *> (Join-Path $work 'build.log')
    if($LASTEXITCODE -ne 0){throw 'TD process failed'}
    foreach($step in @('read_design','opt_rtl','opt_gate','opt_place','opt_route','bitgen')){
        if(Test-Path -LiteralPath ('.'+$step+'.error.f')){throw "TD failed: $step"}
    }
    $timing=Get-Content -LiteralPath HDMI1.4b_Transmitter_v2.0_pr.timing -Raw
    $setup=[regex]::Match($timing,'SWNS:\s*([-\d.]+)ns,\s*STNS:\s*([-\d.]+)ns')
    $hold=[regex]::Match($timing,'HWNS:\s*([-\d.]+)ns,\s*HTNS:\s*([-\d.]+)ns')
    if(!$setup.Success -or !$hold.Success){throw 'Missing timing status'}
    $culture=[Globalization.CultureInfo]::InvariantCulture
    $sw=[double]::Parse($setup.Groups[1].Value,$culture);$st=[double]::Parse($setup.Groups[2].Value,$culture)
    $hw=[double]::Parse($hold.Groups[1].Value,$culture);$ht=[double]::Parse($hold.Groups[2].Value,$culture)
    if($sw -lt 0 -or $hw -lt 0 -or $st -ne 0 -or $ht -ne 0){throw "Timing failed: $sw/$hw"}
    $area=Get-Content -LiteralPath HDMI1.4b_Transmitter_v2.0_phy.area -Raw
    foreach($budget in @(@('lut',15251),@('bram',55),@('bram32k',11),@('dsp',11))){
        $match=[regex]::Match($area,'(?m)^#'+$budget[0]+'\s+(\d+)\s+out of')
        if(!$match.Success -or [int]$match.Groups[1].Value -gt $budget[1]){throw "No acceptable resource improvement: $($budget[0])"}
    }
    Write-Host "STAGED PASS $work; setup=$sw hold=$hw; protected default untouched"
} finally {Pop-Location}
