from pathlib import Path
import math,numpy as np
from PIL import Image
ROOT=Path(__file__).resolve().parents[1]
def generate():
    # Sixteen rigid foil flip/tumble poses with a slight permanent bow.
    # A 16x16 crop keeps all poses in 4096 four-bit entries, fitting the
    # same physical BRAM allocation as the previous eight larger poses.
    y,x=np.mgrid[0:256,0:256].astype(float)
    x=(x+.5)/8-16;y=(y+.5)/8-16
    silhouettes=[]
    for pose in range(16):
        phase=pose*math.pi/8
        angle=phase/2
        u=x*math.cos(angle)+y*math.sin(angle)
        v=-x*math.sin(angle)+y*math.cos(angle)
        t=np.clip(v/6.5,-1,1)
        center=.45*(1-t*t)
        halfwidth=(.9+2.9*abs(math.cos(phase)))*(.92+.08*(1-t*t))
        mask=(np.abs(u-center)<halfwidth)&(np.abs(v)<=6.5)
        alpha=np.rint(mask.reshape(32,8,32,8).mean(axis=(1,3))*15).astype(np.uint8)
        outside=alpha.copy();outside[8:24,8:24]=0
        assert not np.any(outside)
        silhouettes.append(alpha)
    full=np.array(silhouettes);crop=full[:,8:24,8:24]
    shade_table=np.array([15,14,11,6,3,5,8,11,13,12,9,4,2,6,11,14],dtype=np.uint8)
    references=[]
    for pose in range(16):
        for yy in range(32):
            for xx in range(32):
                references.append(int(full[pose,yy,xx])*16+int(shade_table[pose]))
    source="""// Sixteen antialiased tilted foil flip poses, gentle bow, metallic flashes.
// Four synchronous ports. 4096 4-bit entries retain the 8-BRAM sprite budget.
module award_sprite_rom(input clk,input [13:0] a0,a1,a2,a3,output reg [7:0] q0,q1,q2,q3);
reg [3:0] memory[0:4095];
function [11:0] address;
 input [13:0] a;reg [4:0] x,y;reg [3:0] xx,yy;
 begin x=a[4:0];y=a[9:5];xx=x-5'd8;yy=y-5'd8;
 address=x>=8 && x<24 && y>=8 && y<24 ? {a[13:10],yy,xx} : 12'd0;
 end
endfunction
initial begin
"""
    source+='\n'.join(f" memory[{i}]=4'h{v:x};" for i,v in enumerate(crop.ravel()))+'\nend\n'
    source+='function [3:0] shade;input [3:0] pose;begin case(pose)\n'
    source+=''.join(f" {i}:shade=4'd{v};\n" for i,v in enumerate(shade_table))+' endcase end endfunction\n'
    source+='always @(posedge clk)begin\n'+''.join(f' q{i}<={{memory[address(a{i})],shade(a{i}[13:10])}};\n' for i in range(4))+'end\nendmodule\n'
    (ROOT/'src/user_source/hdl_source/award_sprite_rom.v').write_text(source,encoding='utf-8')
    (ROOT/'tests/fixtures/sprite_reference.hex').write_text('\n'.join(f'{v:02x}' for v in references)+'\n')
    temp=Path('E:/Codex/Temp/saixian_award_preview');temp.mkdir(exist_ok=True)
    sheet=Image.new('RGB',(16*96,96),(16,19,26))
    for pose in range(16):
        a=full[pose].astype(float)/16
        sh=np.full((32,1),shade_table[pose],dtype=np.uint8)
        gold=np.stack([np.broadcast_to(188+sh*4,(32,32)),np.broadcast_to(122+sh*8,(32,32)),np.broadcast_to(46+sh*4,(32,32))],axis=2).astype(float)
        pixels=np.array([16,19,26])+a[:,:,None]*(gold-np.array([16,19,26]))
        sheet.paste(Image.fromarray(pixels.astype(np.uint8)).resize((96,96)),(pose*96,0))
    sheet.save(temp/'ribbon_poses.png')
    print('Generated 16 tilted foil flip poses, 4096 four-bit entries, uniform angular metallic reflection, gentle bow.')
if __name__=='__main__':generate()
