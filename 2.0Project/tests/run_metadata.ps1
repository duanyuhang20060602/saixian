$ErrorActionPreference='Stop'
$cache='E:/Codex/Temp/saixian_2_opt_tests'
New-Item -ItemType Directory -Force -Path $cache | Out-Null
Push-Location (Split-Path $PSScriptRoot -Parent)
try {
    & C:/iverilog/bin/iverilog.exe -g2012 -s tb_media_header -o ($cache+'/header.vvp') tests/tb_media_header.v src/user_source/hdl_source/SD/saixian_media_header.v
    if($LASTEXITCODE -ne 0){throw 'Header compile failed'}
    & C:/iverilog/bin/vvp.exe ($cache+'/header.vvp')
    if($LASTEXITCODE -ne 0){throw 'Header reference failed'}
    # Scanner/controller metadata is isolated from external SD and BMP input.
    & C:/iverilog/bin/iverilog.exe -g2012 -i -s tb_image_metadata -o ($cache+'/metadata.vvp') tests/tb_image_metadata.v src/user_source/hdl_source/SD/sd_card_bmp.v
    if($LASTEXITCODE -ne 0){throw 'Metadata compile failed'}
    & C:/iverilog/bin/vvp.exe ($cache+'/metadata.vvp')
    if($LASTEXITCODE -ne 0){throw 'Metadata reference failed'}
} finally {Pop-Location}
