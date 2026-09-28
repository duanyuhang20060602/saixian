$ErrorActionPreference = "Stop"
$projectRoot = (Resolve-Path $PSScriptRoot).Path
$tdRoot = 'C:\Anlogic\TD_6.2.1_Engineer_6.2.168.116'
if ($env:SAIXIAN_TD_ROOT) { $tdRoot = $env:SAIXIAN_TD_ROOT }
elseif (-not (Test-Path -LiteralPath $tdRoot)) { $tdRoot = 'D:\TD' }
$tdPrompt = Join-Path $tdRoot 'bin\td_commands_prompt.exe'
if (-not (Test-Path -LiteralPath $tdPrompt)) {
    throw "TD command-line tool not found: $tdPrompt"
}
try {
    Push-Location (Join-Path $projectRoot 'src\td_project')
    $backupDir = Join-Path $projectRoot '.build-backup'
    New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
    $lastGood = Join-Path $backupDir 'last_timing_pass.bin'
    $baseline = 'HDMI1.4b_Transmitter_v2.0.bit'
    if (-not (Test-Path -LiteralPath $lastGood) -and (Test-Path -LiteralPath $baseline)) {
        Copy-Item -LiteralPath $baseline -Destination $lastGood
    }
    $buildStarted = Get-Date
    Remove-Item -LiteralPath '.opt_rtl.error.f' -Force -ErrorAction SilentlyContinue
    $previousTdRoot = $env:SAIXIAN_TD_ROOT
    try {
        $env:SAIXIAN_TD_ROOT = $tdRoot.Replace('\','/')
        & $tdPrompt 'build_saixian.tcl'
    } finally {
        $env:SAIXIAN_TD_ROOT = $previousTdRoot
    }
    if ($LASTEXITCODE -ne 0) {
        throw "TD command-line exit code: $LASTEXITCODE"
    }
    if (Test-Path -LiteralPath '.opt_rtl.error.f') {
        throw "TD optimize_rtl failed; inspect the build log."
    }
    # TD may return zero and generate a bitstream despite timing violations.
    # Validate the fresh, post-hold-fix routed report, not an old final report.
    $report = 'HDMI1.4b_Transmitter_v2.0_pr.timing'
    $bit = 'HDMI1.4b_Transmitter_v2.0.bit'
    $timingOK = $false
    if ((Test-Path -LiteralPath $report) -and (Test-Path -LiteralPath $bit) -and
        ((Get-Item -LiteralPath $report).LastWriteTime -ge $buildStarted) -and
        ((Get-Item -LiteralPath $bit).LastWriteTime -ge $buildStarted)) {
        $timing = Get-Content -LiteralPath $report -Raw
        $setup = [regex]::Match($timing, 'SWNS:\s*([-\d.]+)ns,\s*STNS:\s*([-\d.]+)ns')
        $hold = [regex]::Match($timing, 'HWNS:\s*([-\d.]+)ns,\s*HTNS:\s*([-\d.]+)ns')
        $culture = [Globalization.CultureInfo]::InvariantCulture
        if ($setup.Success -and $hold.Success) {
            $swns = [double]::Parse($setup.Groups[1].Value, $culture)
            $stns = [double]::Parse($setup.Groups[2].Value, $culture)
            $hwns = [double]::Parse($hold.Groups[1].Value, $culture)
            $htns = [double]::Parse($hold.Groups[2].Value, $culture)
            $timingOK = $swns -ge 0 -and $hwns -ge 0 -and $stns -eq 0 -and $htns -eq 0
        }
    }
    if (-not $timingOK) {
        if (Test-Path -LiteralPath $bit) {
            Copy-Item -LiteralPath $bit -Destination (Join-Path $backupDir 'TIMING_FAILED_DO_NOT_USE.bin') -Force
        }
        if (Test-Path -LiteralPath $lastGood) {
            Copy-Item -LiteralPath $lastGood -Destination $bit -Force
        }
        throw 'Routed timing failed or output is stale. Default bit restored to last known timing-pass build.'
    }
    Copy-Item -LiteralPath $report -Destination 'final_timing.rpt' -Force
    Copy-Item -LiteralPath $bit -Destination $lastGood -Force
    Write-Host "Routed timing PASS: setup $swns ns, hold $hwns ns"
} finally {
    Pop-Location
}
