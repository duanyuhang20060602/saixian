from pathlib import Path
import subprocess
ROOT=Path(__file__).resolve().parents[1];WORK=Path('E:/Codex/Temp/saixian_softflow720_tests')
tests={'boot':['src/user_source/hdl_source/delta_video.v','src/user_source/hdl_source/award_fx.v','src/user_source/hdl_source/award_sprite_rom.v','tests/tb_boot.v'],
       'status':['src/user_source/hdl_source/delta_status.v','src/user_source/hdl_source/SD/seg_scan.v','src/user_source/hdl_source/SD/seg_decoder.v','tests/tb_status.v'],
       'first_hold':['src/user_source/hdl_source/delta_player.v','src/user_source/hdl_source/delta_decoder.v','tests/tb_first_hold.v'],
       'index':['src/user_source/hdl_source/delta_player.v','src/user_source/hdl_source/delta_decoder.v','tests/tb_index.v'],
       'stream_crc':['src/user_source/hdl_source/delta_player.v','src/user_source/hdl_source/delta_decoder.v','tests/tb_stream_crc.v']}
for name,sources in tests.items():
    binary=WORK/(name+'.vvp')
    subprocess.run(['C:/iverilog/bin/iverilog.exe','-g2012','-s','tb_'+name,'-o',str(binary),*sources],cwd=ROOT,check=True)
    result=subprocess.run(['C:/iverilog/bin/vvp.exe',str(binary)],cwd=ROOT,capture_output=True,text=True)
    (WORK/(name+'.log')).write_text(result.stdout+result.stderr)
    print(result.stdout)
    if result.returncode:raise RuntimeError(name+' failed')
