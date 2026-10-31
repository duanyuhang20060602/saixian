// Caption and eight-runner result input share the original HMI/UART/SD path.
module photo_serial_text_runtime_a #(parameter BOOT_TEXT=0,RANK_INPUT=0)(input clk,rst,input byte_valid,input [7:0] byte_data,
 input can_start,input timeout,input boot_ready,input reply_valid,input [7:0] reply_tag,reply_position,input reply_error,
 output active,output request_valid,output [7:0] tag,bank_length,character_index,
 output [13:0] code,output reg rank_begin,rank_finish,rank_failed,
 output [2:0] rank_index,output [3:0] rank_length,output [15:0] rank_time);
reg [3:0] parse;reg bank,high,bad,loading,rank_target,boot_loading;
reg [1:0] boot_pending;reg [7:0] high_byte,transaction;
reg [4:0] count,length;reg [3:0] index;wire [15:0] code_read;
reg [2:0] rank_candidate;reg [15:0] time_candidate;reg [1:0] time_digits;
assign rank_index=rank_candidate;assign rank_length=count[3:0];assign rank_time=time_candidate;
assign active=parse!=0;
assign request_valid=loading;assign tag=transaction;
assign bank_length=RANK_INPUT && rank_target ? {rank_index,length}:{bank,2'd0,length};
assign character_index={4'd0,index};
function [13:0] boot_code;input b;input [3:0] i;begin
 if(!b)case(i)0:boot_code=49;1,2:boot_code=48;default:boot_code=3378 ;endcase
 else case(i)0:boot_code=2593;1:boot_code=4840;2:boot_code=3061;3:boot_code=2036;4:boot_code=4964;5:boot_code=2116;6:boot_code=2636; default:boot_code=32;endcase
end endfunction
assign code=length==0 ? 14'd32:boot_loading ? boot_code(bank,index):code_read[13:0];
wire [6:0] zone=high_byte[6:0]-7'h21;
wire [6:0] point=byte_data[6:0]-7'h21;
wire [13:0] gb_code=14'd128+(zone<<6)+(zone<<5)-(zone<<1)+point;
// Store the input queue in one freed9K RAM rather than224 flip-flops.
// Read the next address on the same edge that advances the request index.
wire code_write=byte_valid && !bad && count<(parse==6 ? 8:16) &&
 ((parse==3 && byte_data!=13 && byte_data!=10) || (parse==6 && byte_data!=",")) &&
 (high ? byte_data>=8'ha1 && byte_data<=8'hfe : byte_data>=32 && byte_data<127);
wire[15:0] code_write_data=high ? {2'd0,gb_code}:{8'd0,byte_data};
wire first_code=byte_valid && !bad && ((parse==3 && byte_data==13) || (parse==9 && byte_data==10));
wire next_code=reply_valid && loading && reply_tag==transaction && !reply_error &&
 reply_position=={index,3'd7,1'b0} && {1'b0,index}+5'd1<length;
wire[3:0] code_read_address=first_code ? 4'd0:next_code ? index+1'b1:index;
`ifdef RANK_SIM
reg[15:0] code_memory[0:15];reg[15:0] code_q;
always @(posedge clk)begin code_q<=code_memory[code_read_address];if(code_write)code_memory[count[3:0]]<=code_write_data;end
assign code_read=code_q;
`else
EG_LOGIC_BRAM #(.DATA_WIDTH_A(16),.ADDR_WIDTH_A(4),.DATA_DEPTH_A(16),
 .DATA_WIDTH_B(16),.ADDR_WIDTH_B(4),.DATA_DEPTH_B(16),.MODE("DP"),
 .REGMODE_A("NOREG"),.REGMODE_B("NOREG"),.WRITEMODE_A("NORMAL"),.WRITEMODE_B("NORMAL"),
 .RESETMODE("SYNC"),.IMPLEMENT("9K")) code_queue(
 .clka(clk),.rsta(1'b0),.cea(1'b1),.wea(1'b0),.ocea(1'b0),.bea(1'b0),.addra(code_read_address),.dia(16'd0),.doa(code_read),
 .clkb(clk),.rstb(1'b0),.ceb(1'b1),.web(code_write),.oceb(1'b0),.beb(1'b0),.addrb(count[3:0]),.dib(code_write_data),.dob());
`endif
wire free_for_input=!(BOOT_TEXT && (boot_pending!=0 || boot_loading));
always @(posedge clk or posedge rst)begin
 if(rst)begin parse<=0;bank<=0;high<=0;bad<=0;loading<=0;high_byte<=0;transaction<=0;count<=0;length<=0;index<=0;
 rank_target<=0;rank_candidate<=0;time_candidate<=0;time_digits<=0;rank_begin<=0;rank_finish<=0;rank_failed<=0;
 boot_pending<=BOOT_TEXT ? 2:0;boot_loading<=0;end
 else begin
  rank_begin<=0;rank_finish<=0;rank_failed<=0;
  if(reply_valid && loading && reply_tag==transaction)begin
   if(reply_error)begin loading<=0;boot_loading<=0;if(rank_target)rank_failed<=1;end
   else if(reply_position=={index,3'd7,1'b0})begin
    if(length==0 || {1'b0,index}+5'd1==length)begin loading<=0;boot_loading<=0;if(rank_target)rank_finish<=1;end else index<=index+1'b1;
   end
  end
  // Reset restoration reloads the same default glyphs through B's indexed TF
  // loader. No RAM contents or screen power-on timing are assumed to persist.
  if(BOOT_TEXT && boot_pending!=0 && boot_ready && !loading && parse==0)begin
   bank<=boot_pending==1;length<=boot_pending==2 ? 4:7;index<=0;loading<=1;boot_loading<=1;rank_target<=0;
   transaction<={1'b0,transaction[6:0]+7'd1};boot_pending<=boot_pending-1'b1;
  end
  if(timeout)parse<=0;
  if(byte_valid)case(parse)
   0:if(can_start && free_for_input && !loading && byte_data=="@")begin parse<=1;bad<=loading;count<=0;high<=0;end
   1:if(byte_data=="0" || byte_data=="1")begin if(!bad)begin bank<=byte_data[0];rank_target<=0;end parse<=2;end
     else if(RANK_INPUT && byte_data=="R")begin parse<=4;end else parse<=0;
   2:if(byte_data==":")parse<=3;else parse<=0;
   3:if(byte_data==13)begin
    parse<=0;
    if(!bad && !high)begin length<=count;index<=0;transaction<=RANK_INPUT ? {1'b0,transaction[6:0]+7'd1}:transaction+1'b1;loading<=1;end
   end else if(byte_data==10)begin end
   else if(!bad)begin
    if(high)begin high<=0;if(byte_data>=8'ha1 && byte_data<=8'hfe && count<16)begin count<=count+1'b1;end else bad<=1;end
    else if(byte_data>=8'ha1 && byte_data<=8'hfe)begin high<=1;high_byte<=byte_data;end
    else if(byte_data>=32 && byte_data<127 && count<16)begin count<=count+1'b1;end
    else bad<=1;
   end
   4:if(byte_data>="1" && byte_data<="8")begin if(!bad)rank_candidate<=byte_data-"1";parse<=5;end else parse<=0;
   5:if(byte_data==":")parse<=6;else parse<=0;
   6:if(byte_data=="," && !high)begin if(count==0)bad<=1;time_candidate<=0;time_digits<=0;parse<=7;end
    else if(!bad)begin
     if(high)begin high<=0;if(byte_data>=8'ha1 && byte_data<=8'hfe && count<8)begin count<=count+1'b1;end else bad<=1;end
     else if(byte_data>=8'ha1 && byte_data<=8'hfe)begin high<=1;high_byte<=byte_data;end
     else if(byte_data>=32 && byte_data<127 && byte_data!=13 && count<8)begin count<=count+1'b1;end
     else bad<=1;
    end
   7:if(byte_data>="0" && byte_data<="9" && time_digits<2)begin time_candidate<={time_candidate[11:0],byte_data[3:0]};time_digits<=time_digits+1'b1;end
     else if(byte_data=="." && time_digits==2)begin parse<=8;time_digits<=0;end else parse<=0;
   8:if(byte_data>="0" && byte_data<="9" && time_digits<2)begin time_candidate<={time_candidate[11:0],byte_data[3:0]};time_digits<=time_digits+1'b1;end
     else if(byte_data==13 && time_digits==2)parse<=9;else parse<=0;
   9:begin parse<=0;if(byte_data==10 && !bad)begin
    rank_target<=1;rank_begin<=1;
    length<=count;index<=0;transaction<={1'b1,transaction[6:0]+7'd1};loading<=1;
   end end
   default:parse<=0;
  endcase
 end
end
endmodule
