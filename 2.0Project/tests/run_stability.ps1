$ErrorActionPreference = 'Stop'
$iv = 'C:/iverilog/bin/iverilog.exe'
$vvp = 'C:/iverilog/bin/vvp.exe'
if ($env:SAIXIAN_IVERILOG_BIN) {
    $iv = Join-Path $env:SAIXIAN_IVERILOG_BIN 'iverilog.exe'
    $vvp = Join-Path $env:SAIXIAN_IVERILOG_BIN 'vvp.exe'
}
if (-not (Test-Path -LiteralPath $iv) -or -not (Test-Path -LiteralPath $vvp)) {
    throw 'Set SAIXIAN_IVERILOG_BIN to a directory containing iverilog.exe and vvp.exe.'
}
$savedTestPath = $env:PATH
$env:PATH = (Split-Path $iv -Parent) + ';' + $env:PATH
Push-Location (Split-Path $PSScriptRoot -Parent)
try {
    $jobs = @(
        @('tb_key2_short_long', 'tests/tb_key2_short_long.v', 'src/user_source/hdl_source/top_tf_hdmi_audio.v'),
        @('tb_picture_stream', 'tests/tb_picture_stream.v', 'src/user_source/hdl_source/top_tf_hdmi_audio.v'),
        @('tb_result_text_geometry', 'tests/tb_result_text_geometry.v', 'src/user_source/hdl_source/saixian_battle_result_fx_pipelined.v'),
        @('tb_hmi_music', 'tests/tb_hmi_music.v', 'src/user_source/hdl_source/saixian_hmi_uart.v', 'src/user_source/hdl_source/top_tf_hdmi_audio.v'),
        @('tb_hmi_compat', 'tests/tb_hmi_compat.v', 'src/user_source/hdl_source/saixian_hmi_uart.v', 'src/user_source/hdl_source/top_tf_hdmi_audio.v'),
        @('tb_hmi_bidirectional', 'tests/tb_hmi_bidirectional.v', 'src/user_source/hdl_source/saixian_hmi_uart.v', 'src/user_source/hdl_source/top_tf_hdmi_audio.v', 'src/user_source/hdl_source/saixian_event_controller.v'),
        @('tb_sdram_refresh_timer', 'tests/tb_sdram_refresh_timer.v', 'src/user_source/hdl_source/include/sdr_init_ref.enc.v'),
        @('tb_startup_error_policy', 'tests/tb_startup_error_policy.v', 'src/user_source/hdl_source/top_tf_hdmi_audio.v'),
        @('tb_startup_retry_integration', 'tests/tb_startup_retry_integration.v', 'src/user_source/hdl_source/SD/sd_card_bmp.v', 'src/user_source/hdl_source/top_tf_hdmi_audio.v'),
        @('tb_hmi_startup_policy', 'tests/tb_hmi_startup_policy.v', 'src/user_source/hdl_source/top_tf_hdmi_audio.v'),
        @('tb_video_recovery', 'tests/tb_video_recovery.v', 'src/user_source/hdl_source/SD/video_delay.v'),
        @('tb_picture_pipe', 'tests/tb_picture_pipe.v', 'src/user_source/hdl_source/top_tf_hdmi_audio.v'),
        @('tb_picture_width', 'tests/tb_picture_width.v', 'src/user_source/hdl_source/top_tf_hdmi_audio.v'),
        @('tb_gain_exact', 'tests/tb_gain_exact.v', 'src/user_source/hdl_source/top_tf_hdmi_audio.v'),
        @('tb_result_controls', 'tests/tb_result_controls.v', 'src/user_source/hdl_source/saixian_battle_result_fx_pipelined.v'),
        @('tb_frame_config', 'tests/tb_frame_config.v', 'src/user_source/hdl_source/top_tf_hdmi_audio.v'),
        @('tb_frame_handshake', 'tests/tb_frame_handshake.v', 'src/user_source/hdl_source/SD/video_timing_data.v'),
        @('tb_result_raster', 'tests/tb_result_raster.v', 'src/user_source/hdl_source/saixian_battle_result_fx_pipelined.v'),
        @('tb_result_decode', 'tests/tb_result_decode.v', 'src/user_source/hdl_source/saixian_battle_result_fx_pipelined.v'),
        @('tb_result_geometry', 'tests/tb_result_geometry.v', 'src/user_source/hdl_source/saixian_battle_result_fx_pipelined.v'),
        @('tb_result_palette', 'tests/tb_result_palette.v', 'src/user_source/hdl_source/saixian_battle_result_fx_pipelined.v'),
        @('tb_music_start', 'tests/tb_music_start.v', 'src/user_source/hdl_source/top_tf_hdmi_audio.v'),
        @('tb_pcm_pause', 'tests/tb_pcm_pause.v', 'src/user_source/hdl_source/top_tf_hdmi_audio.v'),
        @('tb_boot_load_order', 'tests/tb_boot_load_order.v', 'src/user_source/hdl_source/SD/sd_card_bmp.v'),
        @('tb_load_scaler', 'tests/tb_load_scaler.v', 'src/user_source/hdl_source/SD/bmp_read.v'),
        @('tb_scaler_fraction_zero', 'tests/tb_scaler_fraction_zero.v', 'src/user_source/hdl_source/SD/bmp_read.v'),
        @('tb_scaler_vga_tail', 'tests/tb_scaler_vga_tail.v', 'src/user_source/hdl_source/SD/bmp_read.v'),
        @('tb_scaler_vga_crisp', 'tests/tb_scaler_vga_crisp.v', 'src/user_source/hdl_source/SD/bmp_read.v'),
        @('tb_scaler_pacing', 'tests/tb_scaler_pacing.v', 'src/user_source/hdl_source/SD/bmp_read.v'),
        @('tb_enhance', 'tests/tb_enhance.v', 'src/user_source/hdl_source/top_tf_hdmi_audio.v'),
        @('tb_enhance_numeric', 'tests/tb_enhance_numeric.v', 'src/user_source/hdl_source/top_tf_hdmi_audio.v'),
        @('tb_enhance_detail', 'tests/tb_enhance_detail.v', 'src/user_source/hdl_source/top_tf_hdmi_audio.v'),
        @('tb_pcm_snapshot', 'tests/tb_pcm_snapshot.v', 'src/user_source/hdl_source/saixian_osd_overlay.v')
    )
    foreach ($job in $jobs) {
        $testCache = Join-Path (Split-Path $PSScriptRoot -Parent) '.build-backup/rtl-tests'
        New-Item -ItemType Directory -Force -Path $testCache | Out-Null
        $target = Join-Path $testCache ($job[0] + '.vvp')
        $options = @('-g2012', '-DVICTORY_SIM', '-s', $job[0], '-o', $target)
        if ($job[0] -eq 'tb_sdram_refresh_timer') { $options += @('-DSDRAM_REFRESH_TIMER_SIM', '-I', 'src/td_project') }
        if ($job[0] -in @('tb_frame_config', 'tb_frame_handshake', 'tb_music_start', 'tb_hmi_music', 'tb_boot_load_order', 'tb_startup_retry_integration')) { $options += '-i' }
        $sources = $job[1..($job.Count - 1)]
        & $iv @options @sources
        if ($LASTEXITCODE -ne 0) { throw "Compile failed: $($job[0])" }
        & $vvp $target
        if ($LASTEXITCODE -ne 0) { throw "Simulation failed: $($job[0])" }
    }
} finally { Pop-Location; $env:PATH = $savedTestPath }
