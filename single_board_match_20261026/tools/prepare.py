from pathlib import Path
import json,re,hashlib
from PIL import Image,ImageDraw,ImageFont
ROOT=Path(__file__).resolve().parents[1]
HDL=ROOT/'project/src/user_source/hdl_source'
TD=ROOT/'project/src/td_project'
BASE=Path('D:/qiansai/saixian_key2_tf_workspace_20261015/pitch_quality_20261021/project/src/td_project')
teams=['红队','蓝队','金鹰','飞虎','雷霆','星火']
states=['赛前设置','赛前倒数','比赛进行','比赛暂停','比赛结束']
top='赛显 | 赛事计分'
messages=['选择双方及比赛时长','准备开始','比赛进行中','暂停中 可修正比分','平局 双方并列','获胜']
help_setup=['K1 主队  K2 客队  K3 时长  K4 开始','短按选择双方  默认三十秒快速验收']
help_play=['K1/K2 短按加分 长按减分','K3 暂停或继续  长按K4提前结束']
help_count=['3 2 1 后自动开始比赛','长按K4取消  返回赛前设置']
help_result=['K4 返回设置 开始下一场','本场结果已锁定  平局不判胜方']
extra=['主队','客队','剩余时间','比赛时长','最后十秒','比分范围','分钟','0123456789: /']
alphabet=''.join(dict.fromkeys(''.join([top,*teams,*states,*messages,*help_setup,*help_play,*help_count,*help_result,*extra])))
alphabet=' '+alphabet.replace(' ','')
assert len(alphabet)<=128,len(alphabet)
ids={c:i for i,c in enumerate(alphabet)}
font=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',15)
words=[0]*2048
atlas=Image.new('RGB',(16*16,8*16),'#0b192b')
for i,c in enumerate(alphabet):
 im=Image.new('1',(16,16));d=ImageDraw.Draw(im)
 box=d.textbbox((0,0),c,font=font)
 d.text(((16-(box[2]-box[0]))//2-box[0],(16-(box[3]-box[1]))//2-box[1]),c,font=font,fill=1)
 for y in range(16):words[i*16+y]=sum(int(im.getpixel((x,y)))<<(15-x) for x in range(16))
 atlas.paste(im.convert('RGB'),((i%16)*16,(i//16)*16))
(TD/'match_font.hex').write_text('\n'.join(f'{w:04x}' for w in words)+'\n')
(HDL/'match_font.hex').write_bytes((TD/'match_font.hex').read_bytes())
atlas.resize((512,256)).save(ROOT/'results/font_atlas.png')
def string_function(name,values):
 s=f'function [6:0] {name};input [2:0] sel;input [5:0] p;begin\n {name}=0;case(sel)\n'
 for k,v in enumerate(values):
  s+=f' {k}:case(p)\n'+''.join(f'  {j}:{name}=7\'d{ids[c]};\n' for j,c in enumerate(v))+f'  default:{name}=0;endcase\n'
 return s+f' default:{name}=0;endcase end endfunction\n'
s='// Generated local font glyph lookup. No external text files at runtime.\n'
s+=string_function('team_char',teams)+string_function('state_char',states)
s+=string_function('message_char',messages)
s+=string_function('help_char',[*help_setup,*help_play,*help_count,*help_result])
def fixed(text):return ''.join(f"{j}:cell_glyph=7'd{ids[c]};" for j,c in enumerate(text))
s+='function [6:0] cell_glyph;input [5:0] col;input [4:0] row;reg [2:0] winner;begin\n'
s+='cell_glyph=0;winner=sa>sb ? fa:fb;case(row)\n'
s+=f"1:begin if(col>=2 && col<15)case(col-2){fixed(top)}default:cell_glyph=0;endcase\n"
s+="if(col>=30)cell_glyph=state_char(fs,col-30);end\n"
s+=f"4:begin if(col>=4 && col<6)case(col-4){fixed('主队')}endcase if(col>=29 && col<31)case(col-29){fixed('客队')}endcase end\n"
s+='5:begin if(col>=4 && col<8)cell_glyph=team_char(fa,col-4);if(col>=29 && col<33)cell_glyph=team_char(fb,col-29);end\n'
s+=f"7:if(col>=16 && col<20 && fs!=1 && fs!=4)case(col-16){fixed('剩余时间')}endcase\n"
s+='14:begin if(col>=12 && col<28)begin\n'
s+='if(fs==0)cell_glyph=message_char(0,col-12);else if(fs==1)cell_glyph=message_char(1,col-17);\n'
s+='else if(fs==2)cell_glyph=message_char(2,col-16);else if(fs==3)cell_glyph=message_char(3,col-14);\n'
s+='else if(sa==sb)cell_glyph=message_char(4,col-15);else begin\n'
s+='if(col>=16 && col<18)cell_glyph=team_char(winner,col-16);if(col>=19 && col<21)cell_glyph=message_char(5,col-19);end end end\n'
s+='16:begin if(fs==0)begin\n'
s+=f"if(col>=13 && col<17)case(col-13){fixed('比赛时长')}endcase\n"
s+=f"case(col)18:cell_glyph=7'd{ids['0']};19:cell_glyph=(dur==2 ? 7'd{ids['3']}:dur==3 ? 7'd{ids['5']}:dur==1 ? 7'd{ids['1']}:7'd{ids['0']});20:cell_glyph=7'd{ids[':']};21:cell_glyph=dur==0 ? 7'd{ids['3']}:7'd{ids['0']};22:cell_glyph=7'd{ids['0']};default:;endcase end\n"
s+=f"else if(fs==2 && sec<=10 && col>=16 && col<20)case(col-16){fixed('最后十秒')}endcase end\n"
s+='18,20:if(col>=2)begin\n'
s+='if(fs==0)cell_glyph=help_char(row==18 ? 0:1,col-2);else if(fs==1)cell_glyph=help_char(row==18 ? 4:5,col-2);\n'
s+='else if(fs==4)cell_glyph=help_char(row==18 ? 6:7,col-2);else cell_glyph=help_char(row==18 ? 2:3,col-2);end\n'
s+='default:cell_glyph=0;endcase end endfunction\n'
(HDL/'match_text.vh').write_text(s,encoding='utf-8')
(ROOT/'results/font_map.json').write_text(json.dumps(ids,ensure_ascii=False,indent=2),encoding='utf-8')
# Keep the board-qualified HDMI/PHY and clock IP sources; discard unrelated
# image/music pipelines from the prototype project source list.
p=BASE/'SAIXIAN_PITCH_EXPERIMENT.al'
t=p.read_text(encoding='utf-8-sig').replace('SAIXIAN_PITCH_EXPERIMENT','SAIXIAN_MATCH_SINGLE')
t=re.sub(r'Path="D:/qiansai/[^\"]+"', 'Path="."',t,count=1)
start=t.index('        <Verilog>');end=t.index('        </Verilog>',start)+len('        </Verilog>')
old=t[start:end]
paths=re.findall(r'<File Path="([^"]+)"',old)
keep=[]
for name in paths:
 q=name.lower()
 if 'hdmi1.4b_transmitter_core/' in q or Path(name).name.lower() in {
 'hdmi_phy_warpper.v','lane_lvds_10_1.v','video_rgb_to_axis_640x480.v','audio_arc_calculate.v',
 'saixian_audio_cue.v'}:keep.append(name)
keep+=['../user_source/hdl_source/match_control.v','../user_source/hdl_source/match_render.v','../user_source/hdl_source/match_top.v']
entries=''.join(f'''            <File Path="{name}">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="{i+1}"/>
                </FileInfo>
            </File>
''' for i,name in enumerate(keep))
t=t[:start]+'        <Verilog>\n'+entries+'        </Verilog>'+t[end:]
# Only video PLL IP is used by this self-contained design.
t=re.sub(r'<File Path="([^"]+\.ipc)">.*?</File>',lambda m:m[0] if 'video_pll.ipc' in m[1].lower() else '',t,flags=re.S)
(TD/'SAIXIAN_MATCH_SINGLE.al').write_text(t,encoding='utf-8')
(TD/'SAIXIAN_PITCH_EXPERIMENT.al').unlink(missing_ok=True)
build=(BASE/'build_pitch.tcl').read_text(encoding='utf-8').replace('SAIXIAN_PITCH_EXPERIMENT','SAIXIAN_MATCH_SINGLE')
build=re.sub(r'set IpSDCList .*','set IpSDCList {}',build)
(TD/'build_match.tcl').write_text(build,encoding='utf-8')
(TD/'build_pitch.tcl').unlink(missing_ok=True)
(ROOT/'results/sources.json').write_text(json.dumps(keep,indent=2))
print('Prepared',len(alphabet),'glyphs and',len(keep),'HDL inputs')
