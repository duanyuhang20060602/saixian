$ErrorActionPreference='Stop'
$td='C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/bin/td_commands_prompt.exe'
$started=Get-Date
$saveDir='E:/Codex/Temp/saixian_v3_project_build'
New-Item -ItemType Directory -Force -Path $saveDir | Out-Null
Push-Location (Join-Path $PSScriptRoot 'src/td_project')
try {
 $bit='HDMI1.4b_Transmitter_v3.0.bit'
 $report='HDMI1.4b_Transmitter_v3.0_pr.timing'
 Copy-Item -LiteralPath $bit -Destination (Join-Path $saveDir 'last_timing_pass.bit') -Force
 & $td 'build_saixian.tcl' *> 'build_console.log'
 $log=Get-Content -LiteralPath 'build_console.log' -Raw
 if($LASTEXITCODE -ne 0 -or $log -match '(?m)^\S+ ERROR:'){throw 'TD design/build failure'}
 if(!(Test-Path -LiteralPath $report) -or (Get-Item $report).LastWriteTime -lt $started){throw 'Fresh routed timing missing'}
 $timing=Get-Content -LiteralPath $report -Raw
 $s=[regex]::Match($timing,'SWNS:\s*([-\d.]+)ns,\s*STNS:\s*([-\d.]+)ns')
 $h=[regex]::Match($timing,'HWNS:\s*([-\d.]+)ns,\s*HTNS:\s*([-\d.]+)ns')
 if(!$s.Success -or !$h.Success -or [double]$s.Groups[1].Value -lt 0 -or [double]$s.Groups[2].Value -ne 0 -or [double]$h.Groups[1].Value -lt 0 -or [double]$h.Groups[2].Value -ne 0){throw 'Routed timing failed'}
 if((Get-Item $bit).LastWriteTime -lt $started){throw 'Fresh bit missing'}
 Copy-Item $report 'final_timing.rpt' -Force
 Copy-Item $bit (Join-Path $PSScriptRoot ('releases/'+$bit)) -Force
 Write-Host "Timing passed: setup $($s.Groups[1].Value) ns, hold $($h.Groups[1].Value) ns"
} catch {
 if(Test-Path $bit){Copy-Item $bit (Join-Path $saveDir 'TIMING_FAILED_DO_NOT_USE.bin') -Force}
 Copy-Item (Join-Path $saveDir 'last_timing_pass.bit') $bit -Force
 throw
} finally {Pop-Location}
