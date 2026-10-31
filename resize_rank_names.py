from pathlib import Path
p=Path('5.0project/common/photo_rank_text.v')
s=p.read_text()
s=s.replace('wire [3:0] glyph_row=read_y[4:1]+4\'d1;','''// 24-pixel name cells, matching the score/unit 24-line font box.
// Keep every source glyph row; nearest-neighbour maps 24 pixels to 16.
function [3:0] small_coord;input [4:0] n;begin case(n)
0,1:small_coord=0;2:small_coord=1;3,4:small_coord=2;5:small_coord=3;
6,7:small_coord=4;8:small_coord=5;9,10:small_coord=6;11:small_coord=7;
12,13:small_coord=8;14:small_coord=9;15,16:small_coord=10;17:small_coord=11;
18,19:small_coord=12;20:small_coord=13;21,22:small_coord=14;23:small_coord=15;
default:small_coord=0;endcase end endfunction
reg [2:0] name_character;reg [4:0] name_local_x;
always @*begin
 if(name_x<24)begin name_character=0;name_local_x=name_x;end
 else if(name_x<48)begin name_character=1;name_local_x=name_x-24;end
 else if(name_x<72)begin name_character=2;name_local_x=name_x-48;end
 else if(name_x<96)begin name_character=3;name_local_x=name_x-72;end
 else if(name_x<120)begin name_character=4;name_local_x=name_x-96;end
 else if(name_x<144)begin name_character=5;name_local_x=name_x-120;end
 else if(name_x<168)begin name_character=6;name_local_x=name_x-144;end
 else begin name_character=7;name_local_x=name_x-168;end
end
wire [4:0] name_local_y=read_y-6'd2;
wire [3:0] glyph_row=small_coord(name_local_y);''')
s=s.replace('name_x[7:5],glyph_row','name_character,glyph_row')
s=s.replace('name_y_valid && read_x>=name_start && read_x<name_start+256 && {1\'b0,name_x[7:5]}<lengths[read_entry]',"name_y_valid && read_y>=2 && read_y<26 && read_x>=name_start && read_x<name_start+192 && {1'b0,name_character}<lengths[read_entry]")
s=s.replace('name_col<=name_x[4:1];','name_col<=small_coord(name_local_x);')
p.write_text(s,newline='\n')
p=Path('5.0project/tests/tb_rank_full_glyph.v');s=p.read_text().replace('x<300 && y>=149 && y<181','x<292 && y>=153 && y<177').replace('x<360 && y>=212 && y<244','x<352 && y>=216 && y<240');p.write_text(s,newline='\n')
