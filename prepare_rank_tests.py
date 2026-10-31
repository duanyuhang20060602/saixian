from pathlib import Path
import subprocess
root=Path('5.0project');s=subprocess.check_output(['git','show','HEAD:5.0project/common/photo_relief_remote.v']).decode();s=s[:s.index('endmodule')+len('endmodule')].replace('module photo_relief_shade_kernel','module original_relief_shade_kernel');(root/'tests/previous_relief_shade.v').write_text(s,newline='\n')
# Extend the working UART/index integration test with all eight editable rows.
p=root/'tests/tb_serial_title_index.v';s=p.read_text();s=s.replace('module tb;','module tb;\nwire rank_we;wire [2:0] rank_row;wire [5:0] rank_index;wire [31:0] rank_data;wire [3:0] rank_length;wire [15:0] rank_score;')
s=s.replace(' a(\n',' a(\n .rank_word_valid(rank_we),.rank_word_row(rank_row),.rank_word_index(rank_index),.rank_word_data(rank_data),.rank_word_length(rank_length),\n',1)
s=s.replace('serial_text(.clk(ac)','serial_text(.rank_score(rank_score),.clk(ac)')
idx=s.index('task byte_send;')
s=s[:idx]+'''photo_rank_text rank_cache(.clk(ac),.rst(rst),.frame_tick(frame),.word_valid(rank_we),.word_row(rank_row),.word_index(rank_index),.word_data(rank_data),.word_length(rank_length),.word_score(rank_score),
 .read_valid(1'b0),.rank_view(1'b1),.read_row(3'd0),.read_x(12'd0),.read_y(6'd0),.name_y_valid(1'b0),.digit_y_valid(1'b0),.custom(),.ink());
'''+s[idx:]
idx=s.index('initial begin\n repeat(20)')
s=s[:idx]+'''task start_rank;input integer place;begin byte_send("@");byte_send("R");byte_send("0"+place);byte_send(":");end endtask
task score_send;input integer v;begin byte_send(",");byte_send("1");byte_send("2");byte_send(".");byte_send("3");byte_send("0"+v);end endtask
task check_rank;input integer r;integer c,y,base;reg [15:0] expected;begin
 if(!rank_cache.enabled[r])$fatal(1,"row not committed %0d",r);
 base=(r*2+rank_cache.banks[r])*128;
 if(rank_cache.lengths[r*2+rank_cache.banks[r]]!=2 || rank_cache.scores[r*2+rank_cache.banks[r]]!=(16'h1231+r))$fatal(1,"rank metadata wrong row=%0d",r);
 for(c=0;c<2;c=c+1)for(y=0;y<16;y=y+1)begin
 expected={8'((((c==0 ? 85:1538)*32+y*2))&255),8'((((c==0 ? 85:1538)*32+y*2+1))&255)};
 if(rank_cache.glyphs.memory[base+c*16+y]!==expected)$fatal(1,"rank glyph wrong %0d %0d %0d",r,c,y);
 end
end endtask
'''+s[idx:]
needle=' $display("PASS indexed sector'
a=s.index(needle)
s=s[:a]+''' for(n=1;n<=8;n=n+1)begin
  start_rank(n);byte_send("U");byte_send(8'hb0);byte_send(8'ha1);score_send(n);end_line;check_rank(n-1);
 end
 // Replace one row with the longest supported name; others must keep their banks and scores.
 start_rank(4);repeat(8)byte_send("A");score_send(9);end_line;
 if(rank_cache.lengths[3*2+rank_cache.banks[3]]!=8 || rank_cache.scores[3*2+rank_cache.banks[3]]!=16'h1239)$fatal(1,"8-char replacement failed");
 check_rank(0);check_rank(7);
 // Invalid name length/score never starts loading or publishes a partial row.
 start_rank(1);repeat(9)byte_send("B");score_send(0);byte_send(13);repeat(80)@(negedge ac);check_rank(0);
 start_rank(1);byte_send("C");byte_send(",");byte_send("1");byte_send(".");byte_send("2");byte_send(13);repeat(80)@(negedge ac);check_rank(0);
'''+s[a:]
s=s.replace('PASS indexed sector font library','PASS editable rankings plus indexed sector font library')
(root/'tests/tb_editable_rank_uart.v').write_text(s,newline='\n')
p=Path('run_index_test.py');s=p.read_text().replace('validation-indexed-title','validation-rank-uart').replace('tests/tb_serial_title_index.v','tests/tb_editable_rank_uart.v').replace("'common/photo_serial_text.v',","'common/photo_serial_text.v','common/photo_rank_text.v',").replace("'PASS indexed'","'PASS editable'")
Path('run_rank_uart_test.py').write_text(s,newline='\n')
