$ErrorActionPreference = "Stop"
$projectRoot = (Resolve-Path $PSScriptRoot).Path
$tdRoot = 'C:\Anlogic\TD_6.2.1_Engineer_6.2.168.116'
$tdPrompt = Join-Path $tdRoot 'bin\td_commands_prompt.exe'
if (-not (Test-Path -LiteralPath $tdPrompt)) {
    throw "未找到 TD 命令行：$tdPrompt"
}
try {
    Push-Location (Join-Path $projectRoot 'src\td_project')
    Remove-Item -LiteralPath '.opt_rtl.error.f' -Force -ErrorAction SilentlyContinue
    & $tdPrompt 'build_saixian.tcl'
    if ($LASTEXITCODE -ne 0) {
        throw "TD 命令行退出码为 $LASTEXITCODE。"
    }
    if (Test-Path -LiteralPath '.opt_rtl.error.f') {
        throw "TD 在 optimize_rtl 阶段失败；请查看终端输出。"
    }
} finally {
    Pop-Location
}
