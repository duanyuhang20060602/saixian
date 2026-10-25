from pathlib import Path
import re
ROOT=Path(__file__).resolve().parents[1]
OLD=ROOT.parents[1]/'saixian/2.0Project'
def put(name,text):
    # Legacy benches sometimes returned exit 0 on failure; make them fatal.
    text=re.sub(r'\$display\(("FAIL[^;]+)\);\$finish;',r'$fatal(1,\1);',text)
    (ROOT/'tests'/name).write_text(text,encoding='utf-8')
legacy=OLD/'dual_board_1080p_still/dual_board_1280x720'
text=(legacy/'tb_bmp.v').read_text(encoding='utf-8').replace('bmp_read #(.SINGLE_IMAGE_MODE(1))','bmp_read')
text=text.replace('wait(scan_done);wait(ready);@(negedge clk);','wait(scan_done);wait(ready);repeat(2)@(negedge clk);')
put('tb_bmp.v',text)
text=(legacy/'tb_scaler.v').read_text(encoding='utf-8')
text=text[:text.index('module tb_scaler;')]+'''module tb_scaler;
wire done;
scaler_case #(.SW(640),.SH(360),.PACE(16),.PIXEL_PERIOD(192),.ROWS(3)) prefix(done);
initial begin wait(done);$finish;end
initial begin #10000000;$fatal(1,"scaler timeout");end
endmodule
'''
put('tb_scaler.v',text)
put('tb_photo_pipeline.v',(OLD/'tests/tb_photo_pipeline.v').read_text(encoding='utf-8'))
