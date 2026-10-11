// Two frame buffers stay identical after each commit by replaying the delta
// into the old, now-inactive buffer. No full-frame copy per animation frame.
module delta_player #(parameter FRAME_WORDS=115200,parameter TICKS_PER_FRAME=825000,parameter INITIAL_HOLD_TICKS=0,parameter VERIFY_STREAM=0,parameter WAIT_PATCH_DRAIN=0)(
 input clk,input rst,input cache_ready,input [20:0] file_words,input [5:0] frame_count,
 output stream_start,output [20:0] stream_offset,output [20:0] stream_words,input stream_ack,
 input [31:0] cmd_data,input cmd_valid,output cmd_pop,
 output patch_valid,output [20:0] patch_addr,output [31:0] patch_data,input patch_ready,
 output reg publish_toggle,output reg publish_slot,input commit_toggle,input pause,
 output reg [3:0] error,output reg [31:0] late_count,
 output reg [5:0] source_frame,output reg [5:0] descriptor,output reg [4:0] state,
 output [191:0] debug_data,input patch_drained
);
localparam WAIT=0,INDEX_START=1,INDEX_READ=2,DATA_START=3,DECODE_START=4,
 DECODE_WAIT=5,WAIT_TIME=6,WAIT_COMMIT=7,VERIFY_START=8,VERIFY_READ=9;
reg [2:0] index_word;reg [31:0] offset,words,duration,next_duration;
reg [31:0] clock_ticks,deadline;reg [20:0] data_offset,data_words;
reg target,active,mirror,bootstrap,bootstrap_second;
reg decode_start;wire decode_done,decode_error,decode_busy,decode_pop;
reg [31:0] expected_crc,stream_crc;reg [20:0] verify_left;
wire [31:0] decoded_crc;wire [3:0] decode_kind;wire [95:0] decode_fault;
assign debug_data={expected_crc,stream_crc^32'hffffffff,decoded_crc,decode_fault};
function [31:0] crc_word;
 input [31:0] old,word;reg [31:0] c;integer i;
 begin c=old^word;for(i=0;i<32;i=i+1)c=c[0] ? (c>>1)^32'hEDB88320 : c>>1;crc_word=c;end
endfunction
wire passed_deadline=$signed(clock_ticks-deadline)>=0;
assign stream_start=state==INDEX_START || state==DATA_START || state==VERIFY_START;
assign stream_offset=state==INDEX_START ? 21'd128+{12'd0,descriptor,3'b0} : data_offset;
assign stream_words=state==INDEX_START ? 21'd8 : data_words;
assign cmd_pop=state==INDEX_READ || state==VERIFY_READ ? cmd_valid : decode_pop;
delta_decoder #(.WAIT_DRAIN(WAIT_PATCH_DRAIN),.FRAME_WORDS(FRAME_WORDS)) decode(clk,rst,decode_start,target,data_words,cmd_data,cmd_valid,decode_pop,
 patch_valid,patch_addr,patch_data,patch_ready,decode_done,decode_error,decode_busy,
 decode_kind,decode_fault,decoded_crc,patch_drained);
always @(posedge clk)begin
 if(rst)begin
  state<=WAIT;descriptor<=0;index_word<=0;offset<=0;words<=0;duration<=0;next_duration<=0;
  clock_ticks<=0;deadline<=0;data_offset<=0;data_words<=0;target<=0;active<=0;
  mirror<=0;bootstrap<=1;bootstrap_second<=0;decode_start<=0;publish_toggle<=0;
  publish_slot<=0;error<=0;late_count<=0;source_frame<=0;
  expected_crc<=0;stream_crc<=32'hffffffff;verify_left<=0;
 end else begin
  clock_ticks<=clock_ticks+1'b1;decode_start<=0;
  if(decode_error && error==0)error<=decode_kind!=0 ? decode_kind : 4'd9;
  if(error==0)case(state)
   WAIT:if(cache_ready)begin descriptor<=0;target<=0;state<=INDEX_START;end
   INDEX_START:if(stream_ack)begin index_word<=0;state<=INDEX_READ;end
   INDEX_READ:if(cmd_valid)begin
    index_word<=index_word+1'b1;
    case(index_word)
     0:offset<=cmd_data;
     1:words<=cmd_data;
     2:next_duration<=cmd_data;
     4:expected_crc<=cmd_data;
     5:source_frame<=cmd_data[5:0];
     7:begin
      if(offset<384 || offset[6:0]!=0 || offset[31:21]!=0 || words==0 || words[31:21]!=0 ||
         {1'b0,offset}+{1'b0,words}>file_words || next_duration==0 || next_duration>500000000)
       error<=offset<384 || offset[6:0]!=0 || offset[31:21]!=0 ? 4'd11 :
              words==0 || words[31:21]!=0 ? 4'd12 :
              {1'b0,offset}+{1'b0,words}>file_words ? 4'd13 : 4'd14;
      else begin data_offset<=offset[20:0];data_words<=words[20:0];state<=VERIFY_STREAM ? VERIFY_START : DATA_START;end
     end
    endcase
   end
   DATA_START:if(stream_ack)state<=DECODE_START;
   VERIFY_START:if(stream_ack)begin verify_left<=data_words;stream_crc<=32'hffffffff;state<=VERIFY_READ;end
   VERIFY_READ:if(cmd_valid)begin
    stream_crc<=crc_word(stream_crc,cmd_data);verify_left<=verify_left-1'b1;
    if(verify_left==1)begin
     if((crc_word(stream_crc,cmd_data)^32'hffffffff)!=expected_crc)error<=7;
     else state<=DATA_START;
    end
   end
   DECODE_START:begin decode_start<=1;state<=DECODE_WAIT;end
   DECODE_WAIT:if(decode_done)begin
    if(VERIFY_STREAM && decoded_crc!=expected_crc)error<=8;
    else if(bootstrap && !bootstrap_second)begin
     bootstrap_second<=1;target<=1;state<=DATA_START;
    end else if(bootstrap)begin
     target<=0;publish_slot<=0;publish_toggle<=~publish_toggle;state<=WAIT_COMMIT;
    end else if(mirror)begin
     mirror<=0;target<=!active;
     descriptor<=descriptor==frame_count ? 6'd1 : descriptor+1'b1;state<=INDEX_START;
    end else state<=WAIT_TIME;
   end
   WAIT_TIME:if(!pause && passed_deadline)begin
    if($signed(clock_ticks-deadline)>=TICKS_PER_FRAME)late_count<=late_count+1'b1;
    publish_slot<=target;publish_toggle<=~publish_toggle;state<=WAIT_COMMIT;
   end
   WAIT_COMMIT:if(commit_toggle==publish_toggle)begin
    active<=publish_slot;
    if(bootstrap)begin
     bootstrap<=0;descriptor<=1;target<=1;duration<=next_duration;
     deadline<=clock_ticks+next_duration+INITIAL_HOLD_TICKS;state<=INDEX_START;
    end else begin
     // Pause stops presentation time; resuming does not fast-forward frames.
     deadline<=deadline+next_duration+pause;
     duration<=next_duration;mirror<=1;target<=!publish_slot;state<=DATA_START;
    end
   end
  endcase
  if(pause && state!=WAIT && !bootstrap &&
     !(state==WAIT_COMMIT && commit_toggle==publish_toggle))deadline<=deadline+1'b1;
 end
end
endmodule
