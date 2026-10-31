`timescale 1ns/1ps
// One editable transaction; lines arriving before completion are rejected.
// Store compact glyph indices, rather than full glyphs or a second UART FIFO.
module photo_text_input_a #(parameter HZ=75000000)(
 input clk,rst,byte_valid,input[7:0] byte_data,input ready,
 output capture,output reg valid,output[255:0] line,output reg error);
reg[1:0] state,slot;reg[4:0] length;reg[223:0] codes;
reg[15:0] mask;reg high,mark,bad;
// A UART byte spans thousands of pixel clocks. Reuse one constant adder
// between the two GB2312 bytes instead of inferring a DSP multiplier.
reg[2:0] zone_blocks;reg[3:0] zone_tail;reg[13:0] row_index;
localparam TB=$clog2(HZ+1);reg[TB-1:0] idle;
reg sample_valid,is_ascii,is_gb;reg[7:0] sample_data;
always @(posedge clk or posedge rst)begin
 if(rst)begin sample_valid<=0;sample_data<=0;is_ascii<=0;is_gb<=0;end
 else begin sample_valid<=byte_valid;sample_data<=byte_data;
  is_ascii<=byte_data>=32 && byte_data<127;
  is_gb<=byte_data>=8'ha1 && byte_data<=8'hfe;
 end
end
wire[6:0] zone=sample_data-8'ha1;
wire[13:0] index=row_index+({6'd0,sample_data}-14'ha1);
assign line={slot,length,9'd0,mask,codes};
assign capture=state!=0;
integer c;
always @(posedge clk or posedge rst)begin
 if(rst)begin state<=0;slot<=0;length<=0;codes<=0;mask<=0;high<=0;mark<=0;bad<=0;zone_blocks<=0;zone_tail<=0;row_index<=0;valid<=0;error<=0;idle<=0;end
 else begin
  error<=0;if(valid && ready)valid<=0;
  if(high)begin
   if(zone_blocks!=0)begin zone_blocks<=zone_blocks-1'b1;row_index<=row_index+14'd1504;end
   else if(zone_tail!=0)begin zone_tail<=zone_tail-1'b1;row_index<=row_index+14'd94;end
  end
  if(state==0 || sample_valid)idle<=0;else if(idle==HZ-1)begin state<=0;error<=1;idle<=0;end else idle<=idle+1'b1;
  if(sample_valid)begin
   if(state==0)begin if(sample_data=="@")begin state<=1;bad<=valid;end end
   else if(sample_data==13)begin
    if(state==3 && !bad && !high && !mark && !valid)begin valid<=1;end else error<=1;
    state<=0;
   end else case(state)
    1:if(sample_data>="0" && sample_data<="3")begin if(!valid)slot<=sample_data[1:0];state<=2;end else begin state<=0;error<=1;end
    2:if(sample_data==":")begin state<=3;if(!valid)begin length<=0;mask<=0;codes<=0;high<=0;mark<=0;end end else begin state<=0;error<=1;end
    3:if(!bad && sample_data!=10)begin
     if(high)begin
      high<=0;if(is_gb && length<16 && zone_blocks==0 && zone_tail==0)begin
       for(c=0;c<16;c=c+1)if(length==c)codes[c*14+:14]<=index;
       mask[length[3:0]]<=mark;mark<=0;length<=length+1'b1;end else bad<=1;
     end else if(sample_data=="^" && !mark)mark<=1;
     else if(is_gb)begin zone_blocks<=zone[6:4];zone_tail<=zone[3:0];row_index<=128;high<=1;end
     else if(is_ascii && length<16)begin
      for(c=0;c<16;c=c+1)if(length==c)codes[c*14+:14]<={6'd0,sample_data};
      mask[length[3:0]]<=mark;mark<=0;length<=length+1'b1;end else bad<=1;
    end
   endcase
  end
 end
end
endmodule

// Four reliable 64-bit fragments in the existing UART control scheduler.
module photo_text_bridge_a #(parameter HZ=75000000)(
 input clk,rst,input frame_tick,output text_busy,input[31:0] session,input line_valid,input[255:0] line,output reg line_ready,
 output pending,output[159:0] message,input sent,input received,input[159:0] incoming,
 output reg word_valid,output reg[7:0] word_index,output reg[31:0] word_data,
 output reg[4:0] word_length,output reg[15:0] word_mask);
reg active;reg[1:0] crc_settle;reg[15:0] tx_crc_q;reg[7:0] token;reg[1:0] part;
reg waiting;localparam TB=$clog2(HZ/5+2);reg[TB-1:0] timer;
reg ack_pending;reg[7:0] ack_generation,ack_index;
reg begin_pending;
reg have_generation;reg[7:0] generation;reg[7:0] expected;
reg[31:0] old_session;reg session_match_q,session_changed_q,ack_match_q;
always @(posedge clk or posedge rst)begin
 if(rst)begin session_match_q<=0;session_changed_q<=0;ack_match_q<=0;end
 else begin session_match_q<=incoming[151:120]==session;session_changed_q<=old_session!=session;
  ack_match_q<=incoming[159:152]==41 && incoming[119:112]==token && incoming[111:104]=={6'd0,part};
 end
end
wire[63:0] chunk=line[part*64+:64];wire[15:0] crc,check;
photo_text_crc tx_crc({token,6'd0,part,chunk},crc);
photo_text_crc rx_crc(incoming[119:40],check);
reg[15:0] checked;always @(posedge clk)begin checked<=check;tx_crc_q<=crc;end
assign text_busy=active || (have_generation && expected<128);

assign pending=ack_pending || (active && crc_settle==0 && (!waiting || timer==0));
assign message=ack_pending ? {8'd43,session,ack_generation,ack_index,104'd0}:
 {8'd40,session,token,6'd0,part,chunk,tx_crc_q,8'd0,16'd0};
always @(posedge clk or posedge rst)begin
 if(rst)begin line_ready<=0;crc_settle<=0;active<=0;token<=0;part<=0;waiting<=0;timer<=0;ack_pending<=0;ack_generation<=0;ack_index<=0;begin_pending<=0;have_generation<=0;generation<=0;expected<=0;old_session<=0;word_valid<=0;word_index<=0;word_data<=0;word_length<=0;word_mask<=0;end
 else begin
  old_session<=session;word_valid<=0;line_ready<=0;if(crc_settle!=0)crc_settle<=crc_settle-1'b1;
  if(begin_pending && frame_tick)begin word_valid<=1;begin_pending<=0;ack_pending<=1;end
  if(waiting && timer!=0)timer<=timer-1'b1;
  if(line_valid && !active && !line_ready)begin crc_settle<=2;active<=1;part<=0;waiting<=0;token<=token+1'b1;end
  if(sent)begin if(ack_pending)ack_pending<=0;else begin waiting<=1;timer<=HZ/5;end end
  if(received && session_match_q)begin
   if(ack_match_q && active)begin
    waiting<=0;if(part==3)begin active<=0;line_ready<=1;end else begin part<=part+1'b1;crc_settle<=2;end
   end
   if(incoming[159:152]==42 && incoming[111:104]<128 && incoming[103:96]<=16 && checked==incoming[39:24])begin
    if((incoming[111:104]==0 && (!have_generation || incoming[119:112]!=generation)) ||
       (have_generation && incoming[119:112]==generation && incoming[111:104]==expected))begin
     if(incoming[111:104]==0)begin_pending<=1;else word_valid<=1;word_index<={1'b1,incoming[110:104]};word_data<=incoming[95:64];word_length<=incoming[100:96];word_mask<=incoming[63:48];
     have_generation<=1;generation<=incoming[119:112];expected<=incoming[111:104]+1'b1;
     ack_pending<=incoming[111:104]!=0;ack_generation<=incoming[119:112];ack_index<=incoming[111:104];
    end else if(have_generation && incoming[119:112]==generation && expected!=0 && !begin_pending && incoming[111:104]==expected-1'b1)begin
     ack_pending<=1;ack_generation<=generation;ack_index<=incoming[111:104];
    end
   end
  end
  if(session_changed_q)begin crc_settle<=2;part<=0;waiting<=0;ack_pending<=0;begin_pending<=0;have_generation<=0;expected<=0;end
 end
end
endmodule

