// Commands: 00 skip unchanged pairs, 01 literal pairs, 10 repeated pair.
// Writes are accepted at their unmasked beat; completion waits for bus drain.
module delta_decoder #(parameter WAIT_DRAIN=0)(
 input clk,input rst,input start,input target,
 input [20:0] encoded_words,input [31:0] stream_data,input stream_valid,output stream_pop,
 output patch_valid,output [20:0] patch_addr,output [31:0] patch_data,input patch_ready,
 output reg done,output reg error,output reg busy,
 output reg [3:0] error_kind,output [95:0] fault_data,output [31:0] encoded_crc,input patch_drained
);
localparam IDLE=0,CMD=1,LITERAL=2,FILL_WORD=3,FILL=4,FINISH=5;
reg [2:0] state;reg [20:0] remaining;reg [16:0] cursor,run;
reg [31:0] fill_data;reg target_latch;
reg [31:0] crc,consumed,fault_word,fault_index,fault_cursor,last_command;
assign encoded_crc=crc^32'hffffffff;
assign fault_data={fault_cursor,fault_index,fault_word};
function [31:0] crc_word;
 input [31:0] old,word;reg [31:0] c;integer i;
 begin c=old^word;for(i=0;i<32;i=i+1)c=c[0] ? (c>>1)^32'hEDB88320 : c>>1;crc_word=c;end
endfunction
wire [1:0] kind=stream_data[31:30];wire [29:0] count=stream_data[29:0];
assign patch_valid=busy && ((state==LITERAL && stream_valid)||(state==FILL));
assign patch_addr=(target_latch ? 21'd115200 : 21'd0)+cursor;
assign patch_data=state==FILL ? fill_data : stream_data;
assign stream_pop=busy && stream_valid &&
 ((state==CMD && remaining!=0)||(state==FILL_WORD && remaining!=0)||
  (state==LITERAL && remaining!=0 && patch_ready));
always @(posedge clk)begin
 if(rst)begin state<=IDLE;remaining<=0;cursor<=0;run<=0;fill_data<=0;
  target_latch<=0;done<=0;error<=0;busy<=0;error_kind<=0;
  crc<=32'hffffffff;consumed<=0;fault_word<=0;fault_index<=0;fault_cursor<=0;last_command<=0;end
 else begin
  done<=0;
  if(start && !busy)begin remaining<=encoded_words;cursor<=0;run<=0;
   target_latch<=target;error<=0;busy<=1;state<=CMD;error_kind<=0;
   crc<=32'hffffffff;consumed<=0;fault_word<=0;fault_index<=0;fault_cursor<=0;last_command<=0;end
  else if(busy)begin
   if(stream_pop)begin crc<=crc_word(crc,stream_data);consumed<=consumed+1'b1;end
   case(state)
   CMD:begin
    if(remaining==0)begin
     if(cursor==115200)begin state<=FINISH;end
     else begin error<=1;error_kind<=6;busy<=0;state<=IDLE;
      fault_word<=last_command;fault_index<=consumed;fault_cursor<={15'd0,cursor};end
    end else if(stream_valid)begin
     remaining<=remaining-1'b1;last_command<=stream_data;
     if(kind==3 || count==0 || count>115200-cursor ||
        (kind==1 && count>remaining-1) || (kind==2 && remaining<2))begin
      error<=1;busy<=0;state<=IDLE;
      error_kind<=kind==3 ? 4'd2 : count==0 ? 4'd1 : count>115200-cursor ? 4'd3 :
                   kind==1 && count>remaining-1 ? 4'd4 : 4'd5;
      fault_word<=stream_data;fault_index<=consumed;fault_cursor<={15'd0,cursor};
     end else if(kind==0)begin cursor<=cursor+count[16:0];end
     else begin run<=count[16:0];state<=kind==1 ? LITERAL : FILL_WORD;end
    end
   end
   FILL_WORD:if(stream_valid)begin fill_data<=stream_data;remaining<=remaining-1'b1;state<=FILL;end
   FILL:if(patch_ready)begin cursor<=cursor+1'b1;run<=run-1'b1;if(run==1)state<=CMD;end
   LITERAL:if(stream_valid && patch_ready)begin
    cursor<=cursor+1'b1;remaining<=remaining-1'b1;run<=run-1'b1;if(run==1)state<=CMD;
   end
   FINISH:if(!WAIT_DRAIN || patch_drained)begin busy<=0;done<=1;state<=IDLE;end
   endcase
  end
 end
end
endmodule
