from pathlib import Path
p=Path('5.0project/common/photo_serial_text.v');s=p.read_text();end=s.index('// One glyph at a time;');rest=s[end:]
head='''// Shared UART line parser: title, ticker and eight named ranking rows.
module photo_serial_text_a(input clk,rst,input byte_valid,input [7:0] byte_data,
 input can_start,input timeout,input reply_valid,input [7:0] reply_tag,reply_position,input reply_error,
 output active,output request_valid,output [7:0] tag,bank_length,character_index,
 output [13:0] code,output reg [15:0] rank_score);
reg [2:0] parse;reg bank,high,bad,loading,ranking;reg [2:0] rank_id,score_count;
reg [7:0] high_byte,transaction;reg [15:0] score_input;
reg [4:0] count,length;reg [3:0] index;reg [13:0] codes[0:15];
assign active=parse!=0;assign request_valid=loading;assign tag=transaction;
assign bank_length=ranking ? {rank_id[2],1'b1,rank_id[1:0],length[3:0]}:{bank,2'd0,length};
assign character_index={4'd0,index};assign code=length==0 ? 14'd32:codes[index];
wire [13:0] zone={6'd0,high_byte}-14'ha1,point={6'd0,byte_data}-14'ha1;
wire [13:0] gb_code=14'd128+(zone<<6)+(zone<<5)-(zone<<1)+point;
always @(posedge clk or posedge rst)begin
 if(rst)begin parse<=0;bank<=0;high<=0;bad<=0;loading<=0;ranking<=0;rank_id<=0;score_count<=0;score_input<=0;rank_score<=0;high_byte<=0;transaction<=0;count<=0;length<=0;index<=0;end
 else begin
  if(reply_valid && loading && reply_tag==transaction)begin
   if(reply_error)loading<=0;
   else if(reply_position=={index,3'd7,1'b0})begin
    if(length==0 || {1'b0,index}+5'd1==length)loading<=0;else index<=index+1'b1;
   end
  end
  if(timeout)parse<=0;
  if(byte_valid)case(parse)
   0:if(can_start && byte_data=="@")begin parse<=1;bad<=loading;count<=0;high<=0;score_input<=0;score_count<=0;end
   1:if(byte_data=="0" || byte_data=="1")begin if(!bad)begin bank<=byte_data[0];ranking<=0;end parse<=2;end
     else if(byte_data=="R")begin if(!bad)ranking<=1;parse<=4;end else parse<=0;
   4:if(byte_data>="1" && byte_data<="8")begin if(!bad)rank_id<=byte_data-8'd49;parse<=2;end else parse<=0;
   2:if(byte_data==":")parse<=3;else parse<=0;
   3:if(byte_data==13)begin
    parse<=0;
    if(!bad && !high && !ranking)begin length<=count;index<=0;transaction<=transaction+1'b1;loading<=1;end
   end else if(byte_data==10)begin end
   else if(ranking && byte_data=="," && !high)begin parse<=5;score_count<=0;end
   else if(!bad)begin
    if(high)begin high<=0;if(byte_data>=8'ha1 && byte_data<=8'hfe && count<(ranking ? 8:16))begin codes[count[3:0]]<=gb_code;count<=count+1'b1;end else bad<=1;end
    else if(byte_data>=8'ha1 && byte_data<=8'hfe)begin high<=1;high_byte<=byte_data;end
    else if(byte_data>=32 && byte_data<127 && count<(ranking ? 8:16))begin codes[count[3:0]]<=byte_data;count<=count+1'b1;end
    else bad<=1;
   end
   5:if(byte_data==13)begin
    parse<=0;
    if(!bad && score_count==5)begin length<=count;index<=0;rank_score<=score_input;transaction<=transaction+1'b1;loading<=1;end
   end else if(!bad)begin
    if(score_count==2 && byte_data==".")score_count<=3;
    else if(score_count!=2 && score_count<5 && byte_data>="0" && byte_data<="9")begin score_input<={score_input[11:0],byte_data[3:0]};score_count<=score_count+1'b1;end
    else bad<=1;
   end
   default:parse<=0;
  endcase
 end
end
endmodule

'''
p.write_text(head+rest,newline='\n')
p=Path('5.0project/common/photo_cached_control_a.v');s=p.read_text();s=s.replace(' output reg font_available,font_transfer_complete,',' output rank_word_valid,output [2:0] rank_word_row,output [5:0] rank_word_index,output [31:0] rank_word_data,output [3:0] rank_word_length,\n output reg font_available,font_transfer_complete,')
s=s.replace('assign title_word_valid=title_packet;','assign title_word_valid=title_packet && !incoming[110];\nassign rank_word_valid=title_packet && incoming[110];\nassign rank_word_row={incoming[111],incoming[109:108]};\nassign rank_word_index={incoming[102:100],incoming[99:97]};\nassign rank_word_data=incoming[95:64];assign rank_word_length=incoming[107:104];');p.write_text(s,newline='\n')
p=Path('5.0project/common/photo_control.v');s=p.read_text().replace('assign text_clear=text_bank_length[4:0]==0;','assign text_clear=text_bank_length[6] ? text_bank_length[3:0]==0:text_bank_length[4:0]==0;');p.write_text(s,newline='\n')
