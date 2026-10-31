`timescale 1ns/1ps
module photo_text_tick #(parameter HZ=100000000)(input clk,rst,output reg tick);
localparam DIV=HZ/1000>0 ? HZ/1000:1;
localparam W=$clog2(DIV+1)>0 ? $clog2(DIV+1):1;
reg[W-1:0] count;
always @(posedge clk or posedge rst)begin
 if(rst)begin count<=0;tick<=0;end
 else if(count==DIV-1)begin count<=0;tick<=1;end
 else begin count<=count+1'b1;tick<=0;end
end
endmodule
// Four short CRC stages, then registered packet/ACK predicates. Consumption
// waits four clocks beyond publication; the UART payload remains stable.
module photo_text_crc_pipeline_b(input clk,input[79:0] data,output reg[15:0] crc);
function[15:0] step;input[15:0] seed;input[19:0] d;integer i;reg[15:0] c;begin
 c=seed;for(i=19;i>=0;i=i-1)c={c[14:0],1'b0}^((c[15]^d[i])?16'h1021:16'd0);step=c;
end endfunction
reg[15:0] first,second,third;
wire[15:0] first_d=step(16'hffff,data[79:60]),second_d=step(first,data[59:40]);
wire[15:0] third_d=step(second,data[39:20]),last_d=step(third,data[19:0]);
always @(posedge clk)begin
 first<=first_d;second<=second_d;third<=third_d;crc<=last_d;
end
endmodule
module photo_text_bridge_b #(parameter HZ=100000000)(
 input clk,rst,input[31:0] session,input received,input[159:0] incoming,
 output pending,output[159:0] message,input sent,
 output reg line_valid,output[255:0] line,input line_ready,
 input word_pending,input[7:0] generation,index,input[4:0] length,
 input[31:0] data,input[15:0] mask,output reg word_ack,input tick);
reg[255:0] assembly;reg[7:0] token;reg[2:0] expected;reg have_token;
reg ack_pending;reg[7:0] ack_token,ack_part;
localparam TDIV=HZ/1000>0 ? HZ/1000:1,RETRY=(HZ/5+TDIV-1)/TDIV;
reg waiting;localparam TB=$clog2(RETRY+2);reg[TB-1:0] timer;reg[2:0] settle;reg[31:0] old_session;
wire[15:0] checked,tx_crc_q;
reg[3:0] received_delay;
reg session_match_q,input_kind_q,ack_match_q,crc_match_q,input_allowed_q,ack_allowed_q,session_changed_q;
reg input_event,fresh_event,duplicate_event,word_ack_event;
always @(posedge clk or posedge rst)
 if(rst)begin input_event<=0;fresh_event<=0;duplicate_event<=0;word_ack_event<=0;end
 else begin
  input_event<=received_delay[3] && input_allowed_q && !line_valid;
  fresh_event<=(incoming[111:104]==0 && line_ready && (!have_token || incoming[119:112]!=token)) ||
   (have_token && incoming[119:112]==token && incoming[111:104]==expected);
  duplicate_event<=have_token && incoming[119:112]==token && expected!=0 && incoming[111:104]==expected-1'b1;
  word_ack_event<=received_delay[3] && ack_allowed_q && word_pending;
 end
always @(posedge clk or posedge rst)
 if(rst)begin received_delay<=0;session_match_q<=0;input_kind_q<=0;ack_match_q<=0;crc_match_q<=0;input_allowed_q<=0;ack_allowed_q<=0;session_changed_q<=0;end
 else begin
  received_delay<={received_delay[2:0],received};
  session_match_q<=incoming[151:120]==session;
  input_kind_q<=incoming[159:152]==40 && incoming[111:104]<4;
  ack_match_q<=incoming[159:152]==43 && incoming[119:112]==generation && incoming[111:104]==index;
  crc_match_q<=checked==incoming[39:24];
  input_allowed_q<=session_match_q && input_kind_q && crc_match_q;
  ack_allowed_q<=session_match_q && ack_match_q;
  session_changed_q<=old_session!=session;
 end
photo_text_crc_pipeline_b rx_crc(clk,incoming[119:40],checked);
photo_text_crc_pipeline_b tx_crc(clk,{generation,index,3'd0,length,data,mask,8'd0},tx_crc_q);
assign line=assembly;
assign pending=ack_pending || (word_pending && settle==0 && (!waiting || timer==0));
assign message=ack_pending ? {8'd41,session,ack_token,ack_part,104'd0}:
 {8'd42,session,generation,index,3'd0,length,data,mask,8'd0,tx_crc_q,8'd0,16'd0};
always @(posedge clk or posedge rst)begin
 if(rst)begin assembly<=0;token<=0;expected<=0;have_token<=0;ack_pending<=0;ack_token<=0;ack_part<=0;line_valid<=0;word_ack<=0;waiting<=0;timer<=0;settle<=7;old_session<=0;end
 else begin
  old_session<=session;word_ack<=0;if(settle!=0)settle<=settle-1'b1;
  if(line_valid && line_ready)line_valid<=0;
  if(waiting && timer!=0 && tick)timer<=timer-1'b1;
  if(!word_pending)begin waiting<=0;settle<=7;end
  if(sent)begin if(ack_pending)ack_pending<=0;else begin waiting<=1;timer<=RETRY;end end
  if(input_event)begin
    if(fresh_event)begin
     assembly[incoming[105:104]*64+:64]<=incoming[103:40];token<=incoming[119:112];have_token<=1;expected<=incoming[106:104]+1'b1;
     ack_pending<=1;ack_token<=incoming[119:112];ack_part<=incoming[111:104];
     if(incoming[111:104]==3)line_valid<=1;
    end else if(duplicate_event)begin
     ack_pending<=1;ack_token<=token;ack_part<=incoming[111:104];
    end
  end
  if(word_ack_event)begin waiting<=0;timer<=0;settle<=7;word_ack<=1;end
  if(session_changed_q)begin have_token<=0;expected<=0;line_valid<=0;ack_pending<=0;waiting<=0;end
 end
end
endmodule

// B keeps four compact code strings and only one 16-character glyph cache.
// The existing A ticker bank is reused for publication; no extra A BRAM.
module photo_text_font_b #(parameter HZ=100000000,HOLD_CYCLES=300000000)(
 input clk,rst,input line_valid,input[255:0] line,output line_ready,
 input card_ready,input[3:0] fs_error,output reg request,output reg[31:0] address,
 input byte_valid,input[7:0] byte_data,input sector_end,
 output word_pending,output reg[7:0] generation,index,output[4:0] length,
 output[31:0] data,output[15:0] mask,input word_ack,input[31:0] session,
 output reg font_ready,output reg fault,input tick);
reg[13:0] codes[0:63];reg[4:0] lengths[0:3];reg[15:0] masks[0:3];
reg[2:0] state;localparam HEADER=0,HEADER_WAIT=1,IDLE=2,LOAD=3,LOAD_WAIT=4,SETTLE=5,SEND=6;
reg[1:0] selected,wanted;reg dirty,enabled;reg[3:0] glyph;
reg[4:0] active_length;reg[15:0] active_mask;
reg[8:0] position,offset;reg magic;reg[7:0] first_byte;
reg we;reg[7:0] wa;reg[15:0] wd;
reg replay;reg[31:0] old_session;localparam TDIV=HZ/1000>0 ? HZ/1000:1,HOLD_TICKS=(HOLD_CYCLES+TDIV-1)/TDIV;localparam CB=$clog2(HOLD_TICKS+1);reg[CB-1:0] cycles;
reg committing,commit_phase;reg[3:0] commit_index;wire[255:0] saved_line=line;
reg[13:0] selected_code,commit_code;
// Fixed character slices avoid a variable index-times-14 barrel shifter.
always @*begin
 selected_code=0;
 case(commit_index)
 0:selected_code=saved_line[0+:14];1:selected_code=saved_line[14+:14];
 2:selected_code=saved_line[28+:14];3:selected_code=saved_line[42+:14];
 4:selected_code=saved_line[56+:14];5:selected_code=saved_line[70+:14];
 6:selected_code=saved_line[84+:14];7:selected_code=saved_line[98+:14];
 8:selected_code=saved_line[112+:14];9:selected_code=saved_line[126+:14];
 10:selected_code=saved_line[140+:14];11:selected_code=saved_line[154+:14];
 12:selected_code=saved_line[168+:14];13:selected_code=saved_line[182+:14];
 14:selected_code=saved_line[196+:14];15:selected_code=saved_line[210+:14];
 endcase
end
reg[13:0] code;always @(posedge clk)code<=codes[{selected,glyph}];
wire[1:0] n1=selected+2'd1,n2=selected+2'd2,n3=selected+2'd3;
wire[1:0] following=lengths[n1]!=0?n1:lengths[n2]!=0?n2:lengths[n3]!=0?n3:selected;
// A missing/corrupt font must not leave A's input transaction locked forever.
// Consume and discard input on a font fault; original 5.0 playback can proceed.
assign line_ready=!committing && state==IDLE && (font_ready || fault || fs_error!=0);
assign length=active_length;assign mask=active_mask;
assign word_pending=state==SEND;
wire[15:0] even,odd;assign data={even,odd};
// A queued write completes one clock after leaving LOAD/LOAD_WAIT. It must
// retain wa even if the state has already advanced to SEND.
wire[7:0] ar=we ? wa:state==SEND ? {index[6:0],1'b0}:wa;
`ifdef TYPED_TEXT_SIM
reg[15:0] memory[0:255];reg[15:0] even_q,odd_q;
always @(posedge clk)begin if(we)memory[ar]<=wd;even_q<=memory[ar];odd_q<=memory[{index[6:0],1'b1}];end
assign even=even_q;assign odd=odd_q;
`else
EG_LOGIC_BRAM #(.DATA_WIDTH_A(16),.ADDR_WIDTH_A(8),.DATA_DEPTH_A(256),.DATA_WIDTH_B(16),.ADDR_WIDTH_B(8),.DATA_DEPTH_B(256),.MODE("DP"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),.WRITEMODE_A("NORMAL"),.WRITEMODE_B("NORMAL"),.RESETMODE("SYNC"),.IMPLEMENT("9K")) cache(
 .clka(clk),.cea(1'b1),.ocea(1'b1),.wea(we),.rsta(1'b0),.dia(wd),.addra(ar),.doa(even),.bea(1'b0),
 .clkb(clk),.ceb(1'b1),.oceb(1'b1),.web(1'b0),.rstb(1'b0),.dib(16'd0),.addrb({index[6:0],1'b1}),.dob(odd),.beb(1'b0));
`endif
function[7:0] magic_at;input[2:0] a;begin case(a)0:magic_at="S";1:magic_at="X";2:magic_at="F";3:magic_at="O";4:magic_at="N";5:magic_at="T";6:magic_at="0";default:magic_at="1";endcase end endfunction
integer i;
always @(posedge clk or posedge rst)begin
 if(rst)begin state<=HEADER;selected<=0;wanted<=0;dirty<=0;enabled<=0;glyph<=0;active_length<=0;active_mask<=0;position<=0;offset<=0;magic<=0;first_byte<=0;we<=0;wa<=0;wd<=0;generation<=0;index<=0;request<=0;address<=2209;replay<=0;old_session<=0;cycles<=0;committing<=0;commit_index<=0;commit_phase<=0;commit_code<=0;font_ready<=0;fault<=0;for(i=0;i<4;i=i+1)begin lengths[i]<=0;masks[i]<=0;end end
 else begin
  request<=0;we<=0;old_session<=session;if(old_session!=session)replay<=1;
  if(enabled && tick && cycles<HOLD_TICKS)cycles<=cycles+1'b1;
  if(line_valid && line_ready && !fs_error && !fault)begin committing<=1;commit_index<=0;commit_phase<=0;end
  if(committing)begin
   if(!commit_phase)begin commit_code<=selected_code;commit_phase<=1;end
   else begin
   commit_phase<=0;codes[{saved_line[255:254],commit_index}]<=commit_code;
   if(commit_index==15)begin
    committing<=0;lengths[saved_line[255:254]]<=saved_line[253:249];masks[saved_line[255:254]]<=saved_line[239:224];
    wanted<=saved_line[253:249]!=0 ? saved_line[255:254]:(selected==saved_line[255:254] ? following:selected);dirty<=1;enabled<=1;cycles<=0;
   end else commit_index<=commit_index+1'b1;
   end
  end
  case(state)
   HEADER:if(card_ready && fs_error==0)begin request<=1;address<=2209;position<=0;magic<=1;state<=HEADER_WAIT;end
   HEADER_WAIT:begin
    if(byte_valid)begin if(position<8 && byte_data!=magic_at(position[2:0]))magic<=0;position<=position+1'b1;end
    if(sector_end)begin font_ready<=magic;fault<=!magic;state<=IDLE;end
   end
   IDLE:if(!committing && !(line_valid && line_ready) && font_ready && enabled &&
       (dirty || (cycles==HOLD_TICKS && following!=selected) || replay))begin
    selected<=dirty?wanted:replay?selected:following;dirty<=0;replay<=0;glyph<=0;index<=0;cycles<=0;generation<=generation+1'b1;state<=SETTLE;
   end
   SETTLE:begin
    // The synchronous code lookup needs one clock after selecting a slot.
    active_length<=lengths[selected];active_mask<=masks[selected];
    position<=0;state<=LOAD;
   end
   LOAD:begin
    if(glyph>=active_length)begin
     // Clear unused glyph cells so shortened/deleted strings cannot leak.
     we<=1;wa<={glyph,position[3:0]};wd<=0;
     if(position==15)begin position<=0;if(glyph==15)begin index<=0;state<=SEND;end else glyph<=glyph+1'b1;end else position<=position+1'b1;
    end else begin address<=2210+{22'd0,code[13:4]};offset<={code[3:0],5'd0};position<=0;request<=1;state<=LOAD_WAIT;end
   end
   LOAD_WAIT:begin
    if(byte_valid)begin
     if(position>=offset && {1'b0,position}<{1'b0,offset}+10'd32)begin
      if(!position[0])first_byte<=byte_data;else begin we<=1;wa<={glyph,position[4:1]};wd<={first_byte,byte_data};end
     end
     position<=position+1'b1;
    end
    if(sector_end)begin if(glyph==15)begin index<=0;state<=SEND;end else begin glyph<=glyph+1'b1;state<=SETTLE;end end
   end
   SEND:if(replay)begin index<=0;generation<=generation+1'b1;replay<=0;end else if(word_ack)begin if(index==127)begin state<=IDLE;cycles<=0;end else index<=index+1'b1;end
  endcase
  if(fs_error!=0)begin fault<=1;font_ready<=0;state<=IDLE;end
 end
end
endmodule
