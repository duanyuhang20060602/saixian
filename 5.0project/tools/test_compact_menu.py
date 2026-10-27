"""Compare a complete rendered menu against an independent pixel reference."""
from pathlib import Path
import argparse,hashlib,json,subprocess,time
from PIL import Image
from prepare_compact_menu import CHARS,LABELS,expected
ROOT=Path(__file__).resolve().parents[1]
def main():
    ap=argparse.ArgumentParser();ap.add_argument('--out',type=Path,required=True);a=ap.parse_args()
    out=a.out.resolve();out.mkdir(parents=True,exist_ok=True)
    memory,_,_=expected();(out/'compact.hex').write_text(''.join(f'{v:04x}\n' for v in memory),encoding='ascii')
    (out/'ip_init_map.vh').write_text('localparam HEX_FILE=INIT_FILE=="photo_compact_menu_font.mif" ? "compact.hex":"";\n',encoding='ascii')
    values=[5,4,4,1,4,0,0,1,1,1,0,0,0,5,1]
    labels=['音量','亮度','对比','锐度','饱和','反色','复古','增强','转场','轮播','音图','修复','边光','间隔','同切']
    outputs=['5','4','4','1','4','关','关','1','01','开','频谱','关','关','05秒','开']
    palette=[0x142332,0x20405a,0x334456,0x32b8d4,0xebebeb,0x7de3ff,0xffd166]
    def ink(text,lx,ly,scale=2):
        index=lx//(16*scale)
        if not 0<=index<len(text):return False
        return bool(memory[CHARS.index(text[index])*16+ly//scale] & (1<<(15-(lx//scale)%16)))
    def pixel(x,y):
        if not(64<=x<864 and 80<=y<656):return 0x123456
        p=0
        if 96<=y<128 and 96<=x<224:
            if ink('设置',x-96,y-96):p=5
        elif 144<=y<624:
            row=(y-144)//32;dy=(y-144)%32;v=values[row]
            p=1 if row==14 else 0
            if row in (0,1,2,3,4,7) and 10<=dy<22 and 320<=x<544:
                width=v*({3:72,7:112}.get(row,28));p=3 if x-320<width else 2
            if 96<=x<288 and ink(labels[row],x-96,dy):p=4
            if 608<=x<800 and ink(outputs[row],x-608,dy):p=6
        return palette[p]
    golden=[pixel(x,y) for y in range(720) for x in range(1280)]
    (out/'golden.hex').write_text(''.join(f'{v:06x}\n' for v in golden),encoding='ascii')
    bench=r'''`timescale 1ns/1ps
module tb;
reg clk=0,rst=1,tick=0,de=0;always #5 clk=~clk;
reg [11:0] x=0;reg [10:0] y=0;reg [6:0] ea=0;wire[7:0] ew;wire[23:0] rgb;
reg [23:0] golden[0:921599];reg[15:0] font[0:1023];integer i,j,fd,checks=0;
photo_settings_overlay #(.COMPACT_MENU(1),.MUSIC_SYNC_CONTROL(1),.INTERVAL_CONTROL(1),.SHARED_EDGE_WEIGHT(1),.VIDEO_DELAY(21)) dut(
 .clk(clk),.rst(rst),.frame_tick(tick),.de(de),.settings_mode(1'b1),.updating(1'b0),.x(x),.y(y),.setting_item(4'd14),
 .volume(4'd5),.brightness(4'd4),.contrast(4'd4),.saturation(4'd4),.sharpness(2'd1),.enhancement(2'd1),
 .invert(1'b0),.vintage(1'b0),.effect(5'd1),.edge_enable(1'b0),.auto_enable(1'b1),.waveform_mode(1'b0),.audio_repair_enable(1'b0),
 .music_sync_enable(1'b1),.rgb_in(24'h123456),.rgb_out(rgb),.auto_interval_seconds(5'd5),.edge_weight_address(ea),.edge_weight(ew));
initial begin
 $readmemh("golden.hex",golden);$readmemh("compact.hex",font);
 fd=$fopen("menu.ppm","wb");$fwrite(fd,"P6\n1280 720\n255\n");
 repeat(5)@(negedge clk);rst=0;tick=1;@(negedge clk);tick=0;repeat(25)@(negedge clk);
 for(i=0;i<921620;i=i+1)begin
  @(negedge clk);x=i%1280;y=i/1280;de=i<921600;ea=i%128;
  @(posedge clk);#1;
  if(ew!==(ea[0] ? font[896+(ea>>1)][7:0]:font[896+(ea>>1)][15:8]))$fatal(1,"edge weight changed at %d",ea);
  if(i>=20)begin
   j=i-20;
   if(rgb!==golden[j])$fatal(1,"pixel %d,%d got %h expected %h",j%1280,j/1280,rgb,golden[j]);
   $fwrite(fd,"%c%c%c",rgb[23:16],rgb[15:8],rgb[7:0]);checks=checks+1;
  end
 end
 $fclose(fd);if(checks!=921600)$fatal(1,"incomplete frame");
 $display("PASS compact menu: 921600 pixels, 21-cycle geometry, 15 labels, separate sync row, concurrent unchanged edge weights");$finish;
end
endmodule
'''
    (out/'menu.v').write_text(bench,encoding='ascii')
    vendor=Path('C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/ip/depot/AXI_Ethernet_Lite_1.0/AXI_Ethernet_Lite/RTL/ram_infer.v')
    files=[out/'menu.v',ROOT/'common/photo_settings_overlay.v',ROOT/'common/photo_menu_font.v',ROOT/'tests/ip_vendor_ram_adapter.v',vendor]
    iv=ROOT.parents[1]/'.tools/iverilog/bin/iverilog.exe';binary=out/'menu.vvp';started=time.monotonic()
    r=subprocess.run([str(iv),'-g2012','-I'+str(out),'-s','tb','-o',str(binary),*map(str,files)],cwd=out,capture_output=True,text=True);log=r.stdout+r.stderr
    if r.returncode==0:r=subprocess.run([str(iv.with_name('vvp.exe')),str(binary)],cwd=out,capture_output=True,text=True,timeout=900);log+=r.stdout+r.stderr
    (out/'menu.log').write_text(log,encoding='utf-8');print(log[-3000:])
    passed=r.returncode==0 and 'PASS ' in log
    (out/'results.json').write_text(json.dumps({'passed':passed,'pixels':921600,'seconds':time.monotonic()-started,'inputs_sha256':{str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in files}},indent=2),encoding='utf-8')
    assert passed
    im=Image.open(out/'menu.ppm');im.save(out/'menu.png');im.crop((64,80,864,656)).save(out/'menu-detail.png')
if __name__=='__main__':main()
