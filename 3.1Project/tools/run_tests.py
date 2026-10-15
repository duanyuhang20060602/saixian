from pathlib import Path
import subprocess,os,json,time,argparse
ROOT=Path(__file__).resolve().parents[1]
IV=Path(os.environ.get('IVERILOG',str(ROOT.parents[1]/'.tools/iverilog/bin/iverilog.exe')))
VVP=IV.with_name('vvp.exe')
out=ROOT/'tests/results';out.mkdir(parents=True,exist_ok=True)
subprocess.run(['python',str(ROOT/'tools/prepare_test_vectors.py')],check=True)
jobs={
 'tb_real_fifo_link_delay':['tests/tb_real_fifo_link_delay.v','common/photo_link.v','projects/board_b/src/user_source/hdl_source/IP/afifo_32_16_256.v','projects/board_b/src/user_source/hdl_source/IP/afifo_16_32_256.v'],
 'tb_real_fifo_link_full':['tests/tb_real_fifo_link_full.v','common/photo_link.v','projects/board_b/src/user_source/hdl_source/IP/afifo_32_16_256.v','projects/board_b/src/user_source/hdl_source/IP/afifo_16_32_256.v'],
 'tb_real_fifo_link':['tests/tb_real_fifo_link.v','common/photo_link.v','projects/board_b/src/user_source/hdl_source/IP/afifo_32_16_256.v','projects/board_b/src/user_source/hdl_source/IP/afifo_16_32_256.v'],
 'tb_no_crc_confirm':['tests/tb_no_crc_confirm.v','common/photo_uart.v','common/photo_control.v'],
 'tb_no_crc_accept':['tests/tb_no_crc_accept.v','common/photo_uart.v','common/photo_control.v'],
 'tb_no_crc_system':['tests/tb_no_crc_system.v','common/photo_uart.v','common/photo_control.v','common/photo_link.v','common/saixian_transition.v'],
 'tb_no_crc_system_async':['tests/tb_no_crc_system_async.v','common/photo_uart.v','common/photo_control.v','common/photo_link.v','common/saixian_transition.v'],
 'tb_pattern_probe':['tests/tb_pattern_probe.v','common/top_photo_pattern_b.v','common/photo_uart.v','common/photo_control.v','common/photo_link.v','common/photo_status.v','projects/board_b/src/user_source/hdl_source/dual_still_reset_sync.v'],
 'tb_system_async':['tests/tb_system_async.v','common/photo_uart.v','common/photo_control.v','common/photo_link.v','common/saixian_transition.v'],
 'tb_crc_display':['tests/tb_crc_display.v','common/photo_status.v'],
 'tb_crc_snapshot':['tests/tb_crc_snapshot.v','common/photo_uart.v','common/photo_control.v'],
 'tb_uart':['tests/tb_uart.v','common/photo_uart.v'],
 'tb_hmi':['tests/tb_hmi.v','common/saixian_hmi_uart.v'],
 'tb_playback_controls':['tests/tb_playback_controls.v','common/photo_processing.v','common/photo_auto_advance.v','common/saixian_transition.v'],
 'tb_confirm':['tests/tb_confirm.v','common/photo_uart.v','common/photo_control.v'],
 'tb_link_timing':['tests/tb_link_timing.v','common/photo_link.v'],
 'tb_cache':['tests/tb_cache.v','common/photo_sd_cache.v'],
 'tb_mapper':['tests/tb_mapper.v','projects/board_a/src/user_source/hdl_source/SD/frame_fifo_read.v'],
 'tb_memory':['tests/tb_memory.v','projects/board_a/src/user_source/hdl_source/SD/frame_fifo_read.v','projects/board_a/src/user_source/hdl_source/SD/frame_fifo_write.v'],
 'tb_photo_pipeline':['tests/tb_photo_pipeline.v','common/photo_processing.v'],
 'tb_render':['tests/tb_render.v','common/top_photo_a.v','common/photo_cached_control_a.v','common/photo_resolution_overlay.v','common/photo_status.v','common/photo_uart.v','common/photo_control.v','common/photo_link.v','common/photo_processing.v','common/photo_auto_advance.v','common/saixian_hmi_uart.v','common/saixian_key_debounce.v','common/saixian_transition.v','projects/board_a/src/user_source/hdl_source/dual_still_reset_sync.v','projects/board_a/src/user_source/hdl_source/frame_pixels.v','projects/board_a/src/user_source/hdl_source/hdmi_minimal_tx.v','projects/board_a/src/user_source/hdl_source/hdmi_output_diagnostics.v'],
 'tb_scaler':['tests/tb_scaler.v','common/photo_sd/bmp_read.v','common/photo_sd/saixian_media_header.v'],
 'tb_scaler_full':['tests/tb_scaler.v','tests/tb_scaler_full.v','common/photo_sd/bmp_read.v','common/photo_sd/saixian_media_header.v'],
 'tb_vga_720':['tests/tb_vga_720.v','common/photo_sd/bmp_read.v','common/photo_sd/saixian_media_header.v'],
 'tb_bmp':['tests/tb_bmp.v','common/photo_sd/bmp_read.v','common/photo_sd/saixian_media_header.v'],
 'tb_system':['tests/tb_system.v','common/photo_uart.v','common/photo_control.v','common/photo_link.v','common/saixian_transition.v'],
}
jobs['tb_read_data_align']=['tests/tb_read_data_align.v','tests/read_alignment_reference.v','projects/board_a/src/user_source/hdl_source/frame_store.v','projects/board_a/src/user_source/hdl_source/SD/frame_read_write.v','projects/board_a/src/user_source/hdl_source/SD/frame_fifo_read.v','projects/board_a/src/user_source/hdl_source/SD/frame_fifo_write.v','projects/board_a/src/user_source/hdl_source/IP/afifo_16_32_256.v','projects/board_a/src/user_source/hdl_source/IP/afifo_32_16_256.v']
parser=argparse.ArgumentParser()
parser.add_argument('--only',nargs='+',choices=list(jobs))
parser.add_argument('--report',default='results.json')
args=parser.parse_args()
results=[]
for name,files in jobs.items():
 if args.only and name not in args.only:continue
 start=time.monotonic();exe=out/(name+'.vvp')
 build=subprocess.run([str(IV),'-g2012','-s',name,'-o',str(exe)]+files,cwd=ROOT,capture_output=True,text=True)
 if build.returncode:print(build.stdout+build.stderr);raise SystemExit(build.returncode)
 run=subprocess.run([str(VVP),str(exe)],cwd=ROOT,capture_output=True,text=True,timeout=600)
 (out/(name+'.log')).write_text(run.stdout+run.stderr,encoding='utf-8')
 print(run.stdout+run.stderr,flush=True)
 passed=run.returncode==0 and 'FATAL' not in run.stdout+run.stderr and 'PASS' in run.stdout
 results.append({'test':name,'passed':passed,'seconds':round(time.monotonic()-start,2)})
 (out/args.report).write_text(json.dumps(results,indent=2),encoding='utf-8')
 if not passed:raise SystemExit(run.returncode or 1)
