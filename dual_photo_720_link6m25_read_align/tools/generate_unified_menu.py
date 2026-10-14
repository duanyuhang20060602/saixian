"""Extend the existing FPGA glyph ROM and generate the unified 720p menu."""
from pathlib import Path
import re
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
labels = {
    0: "综合设置", 8: "切换方式", 9: "自动轮播", 14: "音量", 15: "音频显示",
    16: "频谱", 17: "波形", 18: "关闭", 19: "开启", 20: "随机", 21: "左右滑动",
    22: "中心展开", 23: "百叶窗", 24: "对角", 25: "溶解", 26: "渐暗",
}
glyphs = {}
for label in labels.values():
    for ch in label:
        if ch not in glyphs:
            glyphs[ch] = 48 + len(glyphs)
assert max(glyphs.values()) < 128
font_path = Path("C:/Windows/Fonts/msyh.ttc")
if not font_path.exists():
    font_path = Path("C:/Windows/Fonts/simhei.ttf")
font = ImageFont.truetype(str(font_path), 15)
mif_path = ROOT / "common/photo_menu_font.mif"
memory = [0] * 2048
for address, value in re.findall(r"(?m)^([0-9A-Fa-f]+)\s*:\s*([0-9A-Fa-f]+);", mif_path.read_text(encoding="utf-8")):
    memory[int(address, 16)] = int(value, 16)
for ch, glyph in glyphs.items():
    im = Image.new("L", (16, 16), 0)
    draw = ImageDraw.Draw(im)
    left, top, right, bottom = draw.textbbox((0, 0), ch, font=font)
    draw.text(((16-(right-left))//2-left, (16-(bottom-top))//2-top), ch, font=font, fill=255)
    for row in range(16):
        value = sum((1 << (15-col)) for col in range(16) if im.getpixel((col, row)) >= 96)
        memory[glyph*16+row] = value
mif = "WIDTH=16;\nDEPTH=2048;\nADDRESS_RADIX=HEX;\nDATA_RADIX=HEX;\nCONTENT BEGIN\n[000..7FF] : 0000;\n"
mif += "".join(f"{address:03X} : {value:04X};\n" for address, value in enumerate(memory) if value)
mif_path.write_text(mif+"END;\n", encoding="utf-8")

overlay = ROOT / "common/photo_settings_overlay.v"
text = overlay.read_text(encoding="utf-8")
tail = text[text.index("reg [5:0] glyph_s1"):] if "reg [5:0] glyph_s1" in text else text[text.index("reg [6:0] glyph_s1"):]
tail = tail.replace("reg [5:0] glyph_s1", "reg [6:0] glyph_s1")
function = text[text.index("function [5:0] text_glyph") : text.index("wire panel=")] if "function [5:0] text_glyph" in text else text[text.index("function [6:0] text_glyph"):text.index("wire panel=")]
function = function.replace("function [5:0]", "function [6:0]").replace("6'd", "7'd").replace("input [3:0] text_id", "input [4:0] text_id")
for ident, label in labels.items():
    body = f"   {ident}:case(index)\n" + "".join(f"    {i}:text_glyph=7'd{glyphs[ch]};\n" for i, ch in enumerate(label)) + "    default:text_glyph=0;\n   endcase\n"
    pattern = rf"   {ident}:case\(index\).*?   endcase\n"
    if re.search(pattern, function, re.S):
        function = re.sub(pattern, lambda _: body, function, flags=re.S)
    else:
        function = function.replace("   default:text_glyph=0;\n endcase", body+"   default:text_glyph=0;\n endcase")
header = '''`timescale 1ns/1ps
// One frame-locked menu for image, audio and playback controls.
module photo_settings_overlay #(parameter VIDEO_DELAY=21)(
 input clk,rst,frame_tick,de,settings_mode,updating,
 input [11:0] x,input [10:0] y,input [3:0] setting_item,
 input [3:0] volume,brightness,contrast,saturation,input [1:0] sharpness,enhancement,
 input invert,vintage,input [2:0] effect,input auto_enable,waveform_mode,
 input [23:0] rgb_in,output [23:0] rgb_out
);
reg visible,pending;reg [3:0] selected;
reg [3:0] values[0:10];
always @(posedge clk or posedge rst)begin
 if(rst)begin visible<=0;pending<=0;selected<=0;
  values[0]<=5;values[1]<=4;values[2]<=4;values[3]<=1;values[4]<=4;
  values[5]<=0;values[6]<=0;values[7]<=1;values[8]<=0;values[9]<=0;values[10]<=0;
 end else if(frame_tick)begin
  visible<=settings_mode;pending<=updating;selected<=setting_item;
  values[0]<=volume;values[1]<=brightness;values[2]<=contrast;values[3]<={2'd0,sharpness};values[4]<=saturation;
  values[5]<={3'd0,invert};values[6]<={3'd0,vintage};values[7]<={2'd0,enhancement};
  values[8]<={1'b0,effect};values[9]<={3'd0,auto_enable};values[10]<={3'd0,waveform_mode};
 end
end
'''
layout = '''wire panel=de && visible && x>=64 && x<864 && y>=80 && y<624;
wire [10:0] row_y=y-11'd144;
wire [3:0] row_index=row_y[8:5];
wire [4:0] row_local=row_y[4:0];
wire [11:0] label_x=x-12'd96,value_x=x-12'd608;
wire [10:0] label_y=y-11'd96,footer_y=y-11'd560;
reg [6:0] glyph;reg [3:0] font_row,font_col;
reg text_on,highlight,bar,track;reg [3:0] value;reg [8:0] bar_width;
reg [4:0] value_label;
reg [23:0] text_color;
always @*begin
 glyph=0;font_row=0;font_col=0;text_on=0;highlight=0;bar=0;track=0;
 value=0;bar_width=0;value_label=0;text_color=24'hebebeb;
 if(panel)begin
  if(y>=96 && y<128 && x>=96 && x<224)begin
   glyph=text_glyph(0,label_x[8:5]);font_row=label_y[4:1];font_col=label_x[4:1];text_on=1;text_color=24'h7de3ff;
  end else if(y>=96 && y<128 && x>=688 && x<784)begin
   glyph=text_glyph(pending ? 10:11,(x-688)>>5);font_row=label_y[4:1];font_col=(x-688)>>1;text_on=1;
   text_color=pending ? 24'hffd166:24'h7de3ff;
  end else if(y>=144 && y<496 && row_index<=10)begin
   value=values[row_index];highlight=row_index==selected;
   case(row_index)
    0,1,2,4:bar_width={5'd0,value}*9'd28;
    3:bar_width={5'd0,value}*9'd72;
    7:bar_width={5'd0,value}*9'd112;
    default:bar_width=0;
   endcase
   case(row_index)
    5,6,9:value_label=value==0 ? 18:19;
    8:value_label=5'd20+{1'b0,value};
    10:value_label=value==0 ? 16:17;
    default:value_label=0;
   endcase
   if(x>=96 && x<288)begin
    glyph=text_glyph(row_index==0 ? 5'd14:row_index==10 ? 5'd15:{1'b0,row_index},label_x[8:5]);
    font_col=label_x[4:1];font_row=row_local[4:1];text_on=1;
   end else if(x>=608 && x<800)begin
    glyph=value_label!=0 ? text_glyph(value_label,value_x[8:5]):value_x[8:5]==0 ? 7'd35+value:7'd0;
    font_col=value_x[4:1];font_row=row_local[4:1];text_on=1;text_color=24'hffd166;
   end
   if(value_label==0 && row_local>=10 && row_local<22 && x>=320 && x<544)begin track=1;bar=x-320<bar_width;end
  end else if(y>=560 && y<600 && x>=96 && x<400)begin
   if((y<576) || (y>=584))begin
    glyph=text_glyph(y<576 ? 12:13,label_x[8:4]);font_col=label_x[3:0];
    font_row=y<576 ? footer_y[3:0]:(y-584);text_on=1;text_color=24'h7de3ff;
   end
  end
 end
end
'''
overlay.write_text(header+function+layout+tail, encoding="utf-8")
print(f"Generated unified menu and {len(glyphs)} additional glyphs.")
