from pathlib import Path
import json,re
from PIL import Image,ImageDraw,ImageFont
ROOT=Path(__file__).resolve().parents[1];HDL=ROOT/'project/src/user_source/hdl_source';TD=ROOT/'project/src/td_project'
BASE=ROOT/'tools/templates'
teams=['红队','蓝队','金鹰','飞虎','雷霆','星火']
states=['比赛准备','赛前倒数','比分直播','比赛暂停','颁奖庆祝']
pages=['赛事首页','双方介绍','赛程检录','上场结果']
texts=[
 '赛显 | 赛事显示','校园投篮挑战赛','主队','客队','剩余时间','比赛时长','最后十秒',
 '赛前介绍 比分直播 赛后颁奖','赛事轮播','倒计时 | 双方比分','开始一场完整赛事',
 '本场对阵','请选择双方再开始比赛','当前场次','当前对阵','下一场次','待检录 现场确认',
 '请双方代表到场准备','赛事信息与比赛比分自动衔接','尚无比赛结果','完成一场比赛后自动保存',
 '最终成绩','平局 双方并列','获胜','本场结果已锁定','上场结果已自动保存','成绩发布',
 '选择双方及比赛时长','准备开始','比赛进行中','暂停中 可修正比分',
 'K1 主队  K2 客队  K3 时长  K4 开始','长按K4返回赛事轮播',
 'K1/K2 短按加分 长按减分','K3 暂停或继续  长按K4提前结束',
 '3 2 1 后自动开始比赛','长按K4取消 返回比赛准备',
 '颁奖后自动发布成绩并回到轮播','K4立即返回轮播 结果会保留',
 '每页五秒 K1上一页 K2下一页','K3比赛准备 K4直接开赛',
 '0123456789: /','第','场','VS']
alphabet=' 0123456789'+''.join(c for c in dict.fromkeys(''.join([*teams,*states,*pages,*texts])) if c not in ' 0123456789')
assert len(alphabet)<=256,len(alphabet)
ids={c:i for i,c in enumerate(alphabet)}
font=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',15);words=[0]*4096
atlas=Image.new('RGB',(256,256),'#0b192b')
for i,c in enumerate(alphabet):
 im=Image.new('1',(16,16));d=ImageDraw.Draw(im);box=d.textbbox((0,0),c,font=font)
 d.text(((16-(box[2]-box[0]))//2-box[0],(16-(box[3]-box[1]))//2-box[1]),c,font=font,fill=1)
 for y in range(16):words[i*16+y]=sum(int(im.getpixel((x,y)))<<(15-x) for x in range(16))
 atlas.paste(im.convert('RGB'),((i%16)*16,(i//16)*16))
text='\n'.join(f'{w:04x}' for w in words)+'\n';(TD/'match_font.hex').write_text(text);(HDL/'match_font.hex').write_text(text)
atlas.resize((512,512)).save(ROOT/'results/font_atlas.png')
def func(name,vals):
 s=f'function [7:0] {name};input [5:0] sel,p;begin {name}=0;case(sel)\n'
 for k,v in enumerate(vals):s+=f'{k}:case(p)'+''.join(f"{j}:{name}=8'd{ids[c]};" for j,c in enumerate(v))+f'default:{name}=0;endcase\n'
 return s+f'default:{name}=0;endcase end endfunction\n'
s=func('team_char',teams)+func('state_char',states)+func('page_char',pages)+func('text_char',texts)
def text_at(text,col):return f'if(col>={col} && col<{col+len(text)})cell_glyph=text_char({texts.index(text)},col-{col});'
def row(n,code):return f'{n}:begin {code} end\n'
def team_at(col,which):return f'if(col>={col} && col<{col+2})cell_glyph=team_char({which},col-{col});'
s+='function [7:0] cell_glyph;input [5:0] col;input [4:0] row;reg [2:0] winner;begin cell_glyph=0;winner=sa>sb ? fa:fb;\n'
s+='case(row)\n'+row(1,text_at(texts[0],2)+'if(col>=30)begin if(fs==4 && summary)cell_glyph=text_char(26,col-30);else cell_glyph=fs==5 ? page_char(pg,col-30):state_char(fs,col-30);end')
s+=row(3,text_at(texts[1],2)+f"case(col)30:cell_glyph=8'd{ids['第']};31:cell_glyph=8'd{ids['0']}+round_tens;32:cell_glyph=8'd{ids['0']}+round_units;33:cell_glyph=8'd{ids['场']};default:;endcase")
s+='default:;endcase\n'
s+='if(fs==5)begin case(pg)\n0:case(row)\n'
s+=row(5,text_at(texts[7],4))+row(9,text_at('赛事轮播',6))+row(11,text_at('倒计时 | 双方比分',6))+row(14,text_at('开始一场完整赛事',6))
s+='default:;endcase\n1:case(row)\n'
s+=row(4,text_at('主队',4)+text_at('客队',29))+row(5,team_at(4,'fa')+team_at(29,'fb'))
s+=row(7,text_at('本场对阵',16))+row(10,text_at('VS',19))+row(14,text_at('请选择双方再开始比赛',12))
s+='default:;endcase\n2:case(row)\n'
s+=row(6,text_at('当前场次',4)+text_at('当前对阵',14))+row(8,team_at(14,'fa')+text_at('VS',18)+team_at(22,'fb'))
s+=row(10,text_at('下一场次',4)+text_at('待检录 现场确认',14))+row(12,text_at('请双方代表到场准备',4))
s+=row(14,text_at('赛事信息与比赛比分自动衔接',4))
s+='default:;endcase\n3:begin if(lv)begin case(row)\n'
s+=row(4,text_at('主队',4)+text_at('客队',29))+row(5,team_at(4,'fa')+team_at(29,'fb'))
s+=row(7,text_at('最终成绩',17))+row(14,'if(sa==sb)begin '+text_at('平局 双方并列',15)+'end else begin '+team_at(16,'winner')+text_at('获胜',19)+'end')
s+=row(16,text_at('上场结果已自动保存',13))+'default:;endcase end else begin case(row)\n'
s+=row(9,text_at('尚无比赛结果',16))+row(13,text_at('完成一场比赛后自动保存',12))+'default:;endcase end end\nendcase\n'
s+='case(row)\n'+row(18,text_at('每页五秒 K1上一页 K2下一页',2))+row(20,text_at('K3比赛准备 K4直接开赛',2))+'default:;endcase end else begin\ncase(row)\n'
s+=row(4,text_at('主队',4)+text_at('客队',29))+row(5,team_at(4,'fa')+team_at(29,'fb'))
s+=row(7,'if(fs==0 || fs==2 || fs==3)begin '+text_at('剩余时间',16)+'end else if(fs==4 && summary)begin '+text_at('最终成绩',17)+'end')
s+=row(14,'if(fs==0)begin '+text_at('选择双方及比赛时长',12)+'end else if(fs==1)begin '+text_at('准备开始',17)+'end else if(fs==2)begin '+text_at('比赛进行中',16)+'end else if(fs==3)begin '+text_at('暂停中 可修正比分',14)+'end else if(fs==4 && summary)begin if(sa==sb)begin '+text_at('平局 双方并列',15)+'end else begin '+team_at(16,'winner')+text_at('获胜',19)+'end end')
s+=row(17,'if(fs==4 && !summary)begin if(sa==sb)begin '+text_at('平局 双方并列',15)+'end else begin '+team_at(16,'winner')+text_at('获胜',19)+'end end')
s+=row(16,'if(fs==0)begin '+text_at('比赛时长',13)+f"case(col)18:cell_glyph=8'd{ids['0']};19:cell_glyph=8'd{ids['0']}+(dur==2 ? 3:dur==3 ? 5:dur==1 ? 1:0);20:cell_glyph=8'd{ids[':']};21:cell_glyph=8'd{ids['0']}+(dur==0 ? 3:0);22:cell_glyph=8'd{ids['0']};default:;endcase end else if(fs==2 && sec<=10)begin "+text_at('最后十秒',16)+'end')
s+='18,20:begin if(fs==0)begin if(row==18)begin '+text_at('K1 主队  K2 客队  K3 时长  K4 开始',2)+'end else begin '+text_at('长按K4返回赛事轮播',2)+'end end\n'
s+='else if(fs==1)begin if(row==18)begin '+text_at('3 2 1 后自动开始比赛',2)+'end else begin '+text_at('长按K4取消 返回比赛准备',2)+'end end\n'
s+='else if(fs==4)begin if(row==18)begin '+text_at('颁奖后自动发布成绩并回到轮播',2)+'end else begin '+text_at('K4立即返回轮播 结果会保留',2)+'end end\n'
s+='else begin if(row==18)begin '+text_at('K1/K2 短按加分 长按减分',2)+'end else begin '+text_at('K3 暂停或继续  长按K4提前结束',2)+'end end end\n'
s+='default:;endcase end\nend endfunction\n'
(HDL/'match_text.vh').write_text(s,encoding='utf-8');(ROOT/'results/font_map.json').write_text(json.dumps(ids,ensure_ascii=False,indent=2),encoding='utf-8')
t=(BASE/'SAIXIAN_PITCH_EXPERIMENT.al').read_text(encoding='utf-8-sig').replace('SAIXIAN_PITCH_EXPERIMENT','SAIXIAN_EVENT_CAROUSEL_SINGLE')
t=re.sub(r'Path="D:/qiansai/[^\"]+"','Path="."',t,count=1);start=t.index('        <Verilog>');end=t.index('        </Verilog>',start)+len('        </Verilog>')
paths=re.findall(r'<File Path="([^"]+)"',t[start:end]);keep=[]
for name in paths:
 if 'hdmi1.4b_transmitter_core/' in name.lower() or Path(name).name.lower() in {'hdmi_phy_warpper.v','lane_lvds_10_1.v','video_rgb_to_axis_640x480.v','audio_arc_calculate.v','saixian_audio_cue.v'}:keep.append(name)
keep += ['../user_source/hdl_source/'+n for n in ['match_control.v','match_render.v','match_top.v','event_flow.v','event_trophy_rom.v']]
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
t=re.sub(r'<File Path="([^"]+\.ipc)">.*?</File>',lambda m:m[0] if 'video_pll.ipc' in m[1].lower() else '',t,flags=re.S)
t=re.sub(r'        <CWC_FILE>.*?</CWC_FILE>','',t,flags=re.S)
(TD/'SAIXIAN_EVENT_CAROUSEL_SINGLE.al').write_text(t,encoding='utf-8')
b=(BASE/'build_pitch.tcl').read_text(encoding='utf-8').replace('SAIXIAN_PITCH_EXPERIMENT','SAIXIAN_EVENT_CAROUSEL_SINGLE');b=re.sub(r'set IpSDCList .*','set IpSDCList {}',b)
(TD/'build_match.tcl').write_text(b,encoding='utf-8')
(ROOT/'results/sources.json').write_text(json.dumps(keep,indent=2))
print('Prepared',len(alphabet),'glyphs and integrated event project')
