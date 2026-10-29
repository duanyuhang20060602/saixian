module photo_relief_tables_compact_a(
 input clk,rst,enable,frame_tick,input [4:0] desired_angle,
 input signed [5:0] desired_light_x,desired_light_y,
 output [31:0] request_descriptor,input request_sent,input [31:0] sent_descriptor,
 output available,input begin_packet,word_valid,finish_packet,commit_packet,
 input [8:0] word_index,input [31:0] word_data,
 output reg active_valid,output reg active_bank,output [4:0] display_angle,
 output signed [5:0] display_light_x,display_light_y,
 output wall_we,output [7:0] wall_wa,output [23:0] wall_wd,
 input mem_clk,mem_rst,mem_enable,
 output palette_we,output [8:0] palette_wa,output [31:0] palette_wd,
 output reg rejected);
 // The compact SPI packet delivers its last word and finish together.
 // Publish one clock later so the final write and count have completed.
 reg finish_q,commit_q;
 always @(posedge clk or posedge rst)
  if(rst)begin finish_q<=0;commit_q<=0;end
  else begin finish_q<=finish_packet;commit_q<=commit_packet;end
 reg previous_enable;reg [7:0] owner;
 
 wire [16:0] parameters={desired_angle,desired_light_x,desired_light_y};
 assign request_descriptor={owner,7'd0,parameters};
 reg [31:0] recent0;
 reg recent_valid;
 reg [31:0] active_descriptor,candidate_descriptor;
 reg receiving,accepted,failed,pending_valid,write_bank;
 reg [8:0] expected_index;
 assign display_angle=active_descriptor[16:12];
 assign display_light_x=active_descriptor[11:6];assign display_light_y=active_descriptor[5:0];
 reg mailbox_request;reg [8:0] mailbox_address;reg [31:0] mailbox_data;
 reg mailbox_ack;(* async_reg="true" *)reg [2:0] ack_sync,mail_sync;
 
 
 wire mailbox_busy=ack_sync[2]!=mailbox_request;
 assign available=enable && !receiving && !pending_valid && !mailbox_busy;
 assign palette_we=mem_enable && mail_sync[2]!=mailbox_ack;
 // Bundled mailbox data is stable before the three-flop request arrives and
 // remains held until the write ACK returns through three source clocks.
 assign palette_wa=mailbox_address;assign palette_wd=mailbox_data;
 always @(posedge mem_clk or posedge mem_rst)
  if(mem_rst)begin mail_sync<=0;mailbox_ack<=0;end
  else begin
   mail_sync<={mail_sync[1:0],mailbox_request};
   
   // ACK on the same edge as the RAM write (or discard after scene exit).
   if(mail_sync[2]!=mailbox_ack)mailbox_ack<=mail_sync[2];
  end
 always @(posedge clk or posedge rst)
  if(rst)ack_sync<=0;else ack_sync<={ack_sync[1:0],mailbox_ack};
 wire matched=recent_valid && word_data==recent0;
 wire data_ok=enable && receiving && accepted && !failed && word_valid && word_index==expected_index;
 assign wall_we=data_ok && word_index>=257 && word_index<=384;
 assign wall_wa={write_bank,(word_index[6:0]-7'd1)};
 assign wall_wd=word_data[31:8];
 always @(posedge clk or posedge rst)
  if(rst)begin previous_enable<=0;owner<=0;
   recent0<=0;recent_valid<=0;active_descriptor<=0;candidate_descriptor<=0;
   active_valid<=0;active_bank<=0;receiving<=0;accepted<=0;failed<=0;pending_valid<=0;write_bank<=1;expected_index<=0;
   mailbox_request<=0;mailbox_address<=0;mailbox_data<=0;rejected<=0;end
  else begin
   previous_enable<=enable;
   if(enable!=previous_enable)begin owner<=owner+1'b1;recent_valid<=0;active_valid<=0;
    pending_valid<=0;receiving<=0;accepted<=0;failed<=0;rejected<=0;end
   else if(enable)begin
    
    if(request_sent)begin recent0<=sent_descriptor;recent_valid<=1;end
    if(frame_tick && pending_valid)begin active_descriptor<=candidate_descriptor;active_bank<=write_bank;active_valid<=1;pending_valid<=0;end
    if(begin_packet && available)begin receiving<=1;accepted<=0;failed<=0;expected_index<=0;write_bank<=!active_bank;end
    if(word_valid && receiving)begin
     expected_index<=expected_index+1'b1;
     if(word_index!=expected_index)failed<=1;
     if(word_index==0)begin accepted<=matched && word_data[31:24]==owner;candidate_descriptor<=word_data;end
     if(data_ok && word_index>=1 && word_index<=256)begin
      if(mailbox_busy)failed<=1;
      else begin mailbox_address<={write_bank,(word_index[7:0]-8'd1)};mailbox_data<=word_data;mailbox_request<=~mailbox_request;end
     end
    end
    if(finish_q)begin
     receiving<=0;
     if(receiving && accepted && !failed && commit_q && expected_index==385 && !mailbox_busy)begin pending_valid<=1;end
     else rejected<=1;
    end
   end
  end
endmodule
