from pathlib import Path
import numpy as np
import hashlib,json,re

ROOT=Path(__file__).resolve().parents[1]
HDL=ROOT/'project/src/user_source/hdl_source'
TD=ROOT/'project/src/td_project'

def edit(text,old,new):
    assert old in text,old[:100]
    return text.replace(old,new,1)

qs=[]
for cutoff in [20000,16000,20000,14000,10500]:
    n=np.arange(63)-31
    h=2*(cutoff/48000)*np.sinc(2*(cutoff/48000)*n)*np.kaiser(63,7)
    h/=h.sum();q=np.rint(h*32768).astype(np.int64);q[31]+=32768-int(q.sum())
    qs.append(q)
lines='\n'.join(f"        9'd{m*64+i}:coefficient={'-' if v<0 else ''}16'sd{abs(int(v))};" for m,q in enumerate(qs) for i,v in enumerate(q))
rtl=(ROOT/'tools/pitch_template.v').read_text().replace('/* COEFFICIENTS */',lines)
(HDL/'saixian_audio_pitch.v').write_text(rtl,encoding='ascii')
np.save(ROOT/'results/fir_q15.npy',np.array(qs))

top=(ROOT/'baseline/top_tf_hdmi_audio.v').read_text(encoding='utf-8')
assert top.count("volume_setting     <= 4'd5;")==2
# Keep startup/default level 5 and the 0..8 control range; boost the curve.
# Nonzero levels select the old level+3 gain; extend above old level 8
# by the existing 1/8-amplitude step. Level 0 remains exact mute.
start=top.index('module saixian_audio_volume ')
end=top.index('endmodule',start)
volume=top[start:end]
volume=volume.replace('// Zero remains mute. Levels 1..6 use original levels 3..8;\n// levels 7..8 add two more steps of 1/8 above unity.',
    '// Zero remains mute. Levels 1..5 select the previous levels 4..8;\n// levels 6..8 extend the previous curve in steps of 1/8 above level 5.')
for old,new in [(2,6),(4,7),(5,8),(6,9),(7,10),(8,11),(9,12),(10,13)]:
    level=[2,4,5,6,7,8,9,10].index(old)+1
    label=str(level) if level<8 else 'default'
    volume=edit(volume,f'{label}: gain={old};',f'{label}: gain={new};')
volume=edit(volume,''' 0:gain_for_level=0;1:gain_for_level=2;2:gain_for_level=4;
 3:gain_for_level=5;4:gain_for_level=6;5:gain_for_level=7;
 6:gain_for_level=8;7:gain_for_level=9;default:gain_for_level=10;''',
''' 0:gain_for_level=0;1:gain_for_level=6;2:gain_for_level=7;
 3:gain_for_level=8;4:gain_for_level=9;5:gain_for_level=10;
 6:gain_for_level=11;7:gain_for_level=12;default:gain_for_level=13;''')
a=volume.index('        case(level)',volume.index('function [7:0] scale_level;'))
b=volume.index('        endcase',a)+len('        endcase')
volume=volume[:a]+'''        case(level)
            0: wide=9'd0;
            1: wide=(value >> 1)+(value >> 2);
            2: wide=value-(value >> 3);
            3: wide=value;
            4: wide={1'b0,value}+(value >> 3);
            5: wide={1'b0,value}+(value >> 2);
            6: wide={1'b0,value}+(value >> 2)+(value >> 3);
            7: wide={1'b0,value}+(value >> 1);
            default: wide={1'b0,value}+(value >> 1)+(value >> 3);
        endcase'''+volume[b:]
top=top[:start]+volume+top[end:]
top=edit(top,'.slide_active(transition_active && !sprint_read_enabled)',".slide_active(1'b0)")
top=edit(top,'wire [23:0] repaired_bg_left, repaired_bg_right;',
    'wire repair_out_valid;\nwire [23:0] repaired_bg_left, repaired_bg_right;')
top=edit(top,'.left_out(repaired_bg_left[23:8]),.right_out(repaired_bg_right[23:8]),.out_valid());',
    '.left_out(repaired_bg_left[23:8]),.right_out(repaired_bg_right[23:8]),.out_valid(repair_out_valid));')
marker="assign repaired_bg_right[7:0]=8'd0;"
top=edit(top,marker,marker+'''
// Experiment KEY2: cycle dry / +4 / -5 / dry+7 / dry+12. Long press -> dry.
reg [2:0] pitch_mode;
always @(posedge video_clk or posedge rst_video) begin
    if(rst_video) pitch_mode<=0;
    else if(carousel_mode && !settings_mode) begin
        if(key2_result_long_press) pitch_mode<=0;
        else if(key2_result_short_press) pitch_mode<=pitch_mode==4 ? 0 : pitch_mode+1'b1;
    end
end
wire signed [15:0] pitched_left,pitched_right;
wire pitch_ready,pitch_overrun,pitch_valid;wire [2:0] pitch_active_mode;
saixian_audio_pitch u_pitch(
    .clk(video_clk),.rst(rst_video),.clear(audio_fifo_reset || !bgm_play_enable),
    .sample_valid(repair_out_valid),.left_in(repaired_bg_left[23:8]),.right_in(repaired_bg_right[23:8]),
    .requested_mode(pitch_mode),.left_out(pitched_left),.right_out(pitched_right),
    .out_valid(pitch_valid),.ready(pitch_ready),.overrun(pitch_overrun),.active_mode(pitch_active_mode));
wire [23:0] effected_bg_left={pitched_left,8'd0},effected_bg_right={pitched_right,8'd0};
''')
# Replace only the mixer/source segment; original repair wires remain connected.
start=top.index('wire signed [24:0] audio_mix_left')
end=top.index('assign audio_level_raw',start)
top=top[:start]+top[start:end].replace('repaired_bg_left','effected_bg_left').replace('repaired_bg_right','effected_bg_right')+top[end:]
top=edit(top,'.visual_low_mode(zoom_mode),',
    '.audio_fx_mode(pitch_mode),.audio_fx_ready(pitch_ready),.visual_low_mode(zoom_mode),')
(HDL/'top_tf_hdmi_audio.v').write_text(top,encoding='utf-8')
osd=(ROOT/'baseline/saixian_osd_overlay.v').read_text(encoding='utf-8')
osd=edit(osd,'input wire visual_low_mode,','input wire visual_low_mode,\n    input wire [2:0] audio_fx_mode,\n    input wire audio_fx_ready,')
marker='        end else if(state==ST_CAROUSEL && !visual_mode && x>=544'
osd=edit(osd,marker,'''        end else if(state==ST_CAROUSEL && x>=336 && x<512 && y>=304 && y<320) begin
            local_x=x-336;slot=local_x[7:4];font_col=local_x[3:0];font_row=y[3:0];
            text_region=1;text_color=audio_fx_ready ? 24'h70E0C0 : 24'hFFC47B;
            case(slot)
                0:glyph_id=87;
                1:glyph_id={4'd0,audio_fx_mode}+7'd1;
                3:glyph_id=audio_fx_mode==0 ? 0 : audio_fx_mode==2 ? 7'd97 : 7'd100;
                4:glyph_id=audio_fx_mode==1 ? 7'd5 : audio_fx_mode==2 ? 7'd6 : audio_fx_mode==3 ? 7'd8 : audio_fx_mode==4 ? 7'd2 : 0;
                5:glyph_id=audio_fx_mode==4 ? 7'd3 : 0;
                7:glyph_id=audio_fx_mode>=3 ? 7'd94 : 0;
                default:glyph_id=0;
            endcase
''' + marker)
(HDL/'saixian_osd_overlay.v').write_text(osd,encoding='utf-8')
al=(ROOT/'baseline/SAIXIAN_FFT_EXPERIMENT.al').read_text(encoding='utf-8')
al=re.sub(r'<Project Version="3" Minor="2" Path="[^"]+"',f'<Project Version="3" Minor="2" Path="{TD.as_posix()}"',al)
al=al.replace('SAIXIAN_FFT_EXPERIMENT','SAIXIAN_PITCH_EXPERIMENT')
al=edit(al,'        </Verilog>','''            <File Path="../user_source/hdl_source/saixian_audio_pitch.v">
                <FileInfo><Attr Name="UsedInSyn" Val="true"/><Attr Name="UsedInP&amp;R" Val="true"/>
                <Attr Name="BelongTo" Val="design_1"/><Attr Name="CompileOrder" Val="200"/></FileInfo>
            </File>
        </Verilog>''')
(TD/'SAIXIAN_PITCH_EXPERIMENT.al').write_text(al,encoding='utf-8')
build=(ROOT/'baseline/build_experiment.tcl').read_text().replace('SAIXIAN_FFT_EXPERIMENT','SAIXIAN_PITCH_EXPERIMENT')
build=build.replace('set phyWildParams {place seed 7}','set phyWildParams {place seed 3}')
(TD/'build_pitch.tcl').write_text(build)
(ROOT/'baseline/input_hashes.json').write_text(json.dumps({p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in (ROOT/'baseline').glob('*.v')},indent=2))
print('Prepared stereo pitch/harmony experiment; playback rate 48k unchanged.')
