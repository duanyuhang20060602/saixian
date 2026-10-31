from pathlib import Path
import json
p=Path('5.0project/common/saixian_battle_result_fx_pipelined.v');s=p.read_text();s=s.replace('    input wire clk, rst, frame_tick, trigger,','    input rank_word_valid,input [2:0] rank_word_row,input [5:0] rank_word_index,input [31:0] rank_word_data,input [3:0] rank_word_length,input [15:0] rank_word_score,\n    input wire clk, rst, frame_tick, trigger,')
s=s.replace('reg pre_row_text_valid;','reg pre_row_text_valid,pre_name_y_valid;reg [5:0] pre_text_y;')
s=s.replace('pre_x<=0; pre_y<=0; pre_row_text_valid<=0;','pre_x<=0; pre_y<=0; pre_row_text_valid<=0;pre_name_y_valid<=0;pre_text_y<=0;')
s=s.replace('pre_x<=raster_x; pre_y<=raster_y; pre_row_text_valid<=row_text_valid;','pre_x<=raster_x; pre_y<=raster_y; pre_row_text_valid<=row_text_valid;\n        pre_text_y<=row_text_offset;pre_name_y_valid<=!row_id[3] && row_text_offset<32 && (rank_mode || raster_y>=row_y);')
idx=s.index('// Three ribboned medals')
s=s[:idx]+'''wire rank_custom,rank_custom_ink;
+photo_rank_text editable_ranking(.clk(clk),.rst(rst),.frame_tick(frame_tick),
+ .word_valid(rank_word_valid),.word_row(rank_word_row),.word_index(rank_word_index),.word_data(rank_word_data),.word_length(rank_word_length),.word_score(rank_word_score),
+ .read_valid((pre_rank || pre_podium) && pre_row_id<8),.rank_view(pre_rank),.read_row(pre_row_id[2:0]),.read_x(pre_row_x_virtual),
+ .read_y(pre_text_y),.name_y_valid(pre_name_y_valid),.digit_y_valid(pre_row_text_valid),.custom(rank_custom),.ink(rank_custom_ink));
+reg [1:0] custom_pipe,custom_ink_pipe;
+always @(posedge clk or posedge rst)
+ if(rst)begin custom_pipe<=0;custom_ink_pipe<=0;end
+ else begin custom_pipe<={custom_pipe[0],rank_custom};custom_ink_pipe<={custom_ink_pipe[0],rank_custom_ink};end
+
+'''.replace('\n+','\n')+s[idx:]
s=s.replace('result_alpha<=result_word_q >> result_bit_offset_q;','result_alpha<=custom_pipe[1] ? {2{custom_ink_pipe[1]}}:result_word_q >> result_bit_offset_q;')
s=s.replace('result_mask<=result_ink_raw;','result_mask<=result_ink_raw || custom_pipe[1];')
p.write_text(s,newline='\n')
p=Path('5.0project/common/top_photo_a.v');s=p.read_text();s=s.replace('wire text_active,text_can_start','wire [15:0] rank_score;wire rank_word_valid;wire [2:0] rank_word_row;wire [5:0] rank_word_index;wire [31:0] rank_word_data;wire [3:0] rank_word_length;\nwire text_active,text_can_start')
s=s.replace('serial_text(.clk(pixel_clk)','serial_text(.rank_score(rank_score),.clk(pixel_clk)')
s=s.replace('ctrl(.text_request(text_request),','ctrl(.rank_word_valid(rank_word_valid),.rank_word_row(rank_word_row),.rank_word_index(rank_word_index),.rank_word_data(rank_word_data),.rank_word_length(rank_word_length),.text_request(text_request),')
s=s.replace('saixian_battle_result_fx u_result_animation(','saixian_battle_result_fx u_result_animation(\n .rank_word_valid(rank_word_valid),.rank_word_row(rank_word_row),.rank_word_index(rank_word_index),.rank_word_data(rank_word_data),.rank_word_length(rank_word_length),.rank_word_score(rank_score),')
p.write_text(s,newline='\n')
td=Path('5.0project/src/board_a/td_project');p=td/'sources.json';files=json.loads(p.read_text());files.append('../../../common/photo_rank_text.v');p.write_text(json.dumps(files,indent=2)+'\n',newline='\n')
p=td/'PHOTO_BOARD_A.al';s=p.read_text();entry='<File Path="../../../common/photo_rank_text.v"><FileInfo><Attr Name="UsedInSyn" Val="true"/><Attr Name="UsedInP&amp;R" Val="true"/><Attr Name="BelongTo" Val="design_1"/><Attr Name="CompileOrder" Val="'+str(len(files)-1)+'"/></FileInfo></File>\n';s=s.replace('</Verilog>',entry+'</Verilog>');p.write_text(s,newline='\n')
