// Small tables cross the existing SPI link; video pixels never cross it.
// Only complete CRC-checked tables become visible, at vertical blanking.
module photo_relief_table_ram #(parameter AW=9,DW=32,IMPLEMENT="9K")(
 input wc,we,input [AW-1:0] wa,input [DW-1:0] wd,
 input rc,input [AW-1:0] ra,output [DW-1:0] rd);
`ifdef RELIEF_SIM
 reg [DW-1:0] memory[0:(1<<AW)-1];reg [DW-1:0] q;
 always @(posedge wc)if(we)memory[wa]<=wd;
 always @(posedge rc)q<=memory[ra];
 assign rd=q;
`else
 EG_LOGIC_BRAM #(.DATA_WIDTH_A(DW),.ADDR_WIDTH_A(AW),.DATA_DEPTH_A(1<<AW),
  .DATA_WIDTH_B(DW),.ADDR_WIDTH_B(AW),.DATA_DEPTH_B(1<<AW),.BYTE_ENABLE(0),
  .MODE("PDPW"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),
  .WRITEMODE_A("NORMAL"),.WRITEMODE_B("NORMAL"),.RESETMODE("SYNC"),.IMPLEMENT(IMPLEMENT)) memory(
  .clka(wc),.rsta(1'b0),.cea(1'b1),.wea(we),.ocea(1'b1),.bea(1'b0),.addra(wa),.dia(wd),.doa(),
  .clkb(rc),.rstb(1'b0),.ceb(1'b1),.web(1'b0),.oceb(1'b1),.beb(1'b0),.addrb(ra),.dib({DW{1'b0}}),.dob(rd));
`endif
endmodule

module photo_relief_coprocessor_b(
 input link_clk,link_rst,relief_start,relief_abort,tap_valid,
 input [19:0] tap_index,input [31:0] tap_data,
 input clk,rst,input spi_clk,spi_rst,packet_active,request_valid,
 input [31:0] request_descriptor,input [8:0] read_address,
 output response_valid,output [31:0] response_descriptor,response_data);
 // Copy raw palettes while the existing, CRC protected asset is transmitted.
 // 24 * 256 words, split to use B's four spare 32K blocks and eight 9K blocks.
 reg capturing,loaded;
 wire pal_write=tap_valid && tap_index>=460864 && tap_index<467008 && capturing;
 wire [12:0] pal_wa=tap_index-20'd460864;
 always @(posedge link_clk or posedge link_rst)
  if(link_rst)begin capturing<=0;loaded<=0;end
  else if(relief_start)begin capturing<=1;loaded<=0;end
  else if(relief_abort && capturing)begin capturing<=0;loaded<=0;end
  else if(pal_write && pal_wa==6143)begin capturing<=0;loaded<=1;end
 reg [4:0] job_angle;reg [8:0] index;
 wire [12:0] pal_ra={job_angle,index[7:0]};
 wire [31:0] head,tail;reg read_tail;
 always @(posedge clk)read_tail<=pal_ra[12];
 photo_relief_table_ram #(.AW(12),.IMPLEMENT("32K")) raw_head(
  .wc(link_clk),.we(pal_write && !pal_wa[12]),.wa(pal_wa[11:0]),.wd(tap_data),
  .rc(clk),.ra(pal_ra[11:0]),.rd(head));
 photo_relief_table_ram #(.AW(11)) raw_tail(
  .wc(link_clk),.we(pal_write && pal_wa[12]),.wa(pal_wa[10:0]),.wd(tap_data),
  .rc(clk),.ra(pal_ra[10:0]),.rd(tail));
 wire [31:0] material=read_tail ? tail:head;
 reg request_toggle;reg [31:0] request_hold;
 always @(posedge spi_clk or posedge spi_rst)
  if(spi_rst)begin request_toggle<=0;request_hold<=0;end
  else if(request_valid)begin request_hold<=request_descriptor;request_toggle<=~request_toggle;end
 (* async_reg="true" *) reg [2:0] query_sync;
 (* async_reg="true" *) reg [31:0] query_meta,query_data;
 (* async_reg="true" *) reg loaded_meta,loaded_sync,active_meta,active_sync;
 reg seen,have_query;reg [31:0] latest,job;
 always @(posedge clk or posedge rst)
  if(rst)begin query_sync<=0;query_meta<=0;query_data<=0;loaded_meta<=0;loaded_sync<=0;active_meta<=0;active_sync<=0;seen<=0;have_query<=0;latest<=0;end
  else begin
   query_sync<={query_sync[1:0],request_toggle};query_meta<=request_hold;query_data<=query_meta;
   loaded_meta<=loaded;loaded_sync<=loaded_meta;active_meta<=packet_active;active_sync<=active_meta;
   if(query_sync[2]!=seen)begin seen<=query_sync[2];latest<=query_data;have_query<=1;end
  end
 reg [2:0] state;reg [4:0] wait_count;
 reg published_bank,published_valid,work_bank;reg [31:0] published_descriptor;
 reg [31:0] kernel_material;reg signed [5:0] lx,ly;
 wire [23:0] lit;
 photo_relief_shade_kernel kernel(.clk(clk),.rst(rst),.material(kernel_material),.light_x(lx),.light_y(ly),
  .wall(index[8]),.wall_level(index[6:0]),.rgb(lit));
 wire table_we=state==3;
 // The antique wall has only 128 response colors. Lossless delta coding
 // stores R8, (G-R/2)5, (B-R/8)4 in one 18-bit A-side RAM port.
 wire [7:0] wall_dg=lit[15:8]-{1'b0,lit[23:17]};
 wire [7:0] wall_db=lit[7:0]-{3'b0,lit[23:19]};
 wire [31:0] table_word=index[8] ? {7'd0,lit[23:16],wall_dg[4:0],wall_db[3:0],7'd0,1'b1}:
  {lit,7'd0,kernel_material[0]};
 (* async_reg="true" *)reg bank_meta,bank_sync,valid_meta,valid_sync;
 (* async_reg="true" *)reg [31:0] descriptor_meta,descriptor_sync;
 always @(posedge spi_clk or posedge spi_rst)
  if(spi_rst)begin bank_meta<=0;bank_sync<=0;valid_meta<=0;valid_sync<=0;descriptor_meta<=0;descriptor_sync<=0;end
  else begin bank_meta<=published_bank;bank_sync<=bank_meta;valid_meta<=published_valid;valid_sync<=valid_meta;
   descriptor_meta<=published_descriptor;descriptor_sync<=descriptor_meta;end
 assign response_valid=valid_sync;assign response_descriptor=descriptor_sync;
 photo_relief_table_ram #(.AW(10)) tables(
  .wc(clk),.we(table_we),.wa({work_bank,index}),.wd(table_word),
  .rc(spi_clk),.ra({bank_sync,read_address}),.rd(response_data));
 always @(posedge clk or posedge rst)
  if(rst)begin state<=0;wait_count<=0;job_angle<=0;index<=0;job<=0;kernel_material<=0;
   lx<=0;ly<=0;published_bank<=0;published_valid<=0;published_descriptor<=0;work_bank<=1;end
  else if(!loaded_sync)begin state<=0;published_valid<=0;end
  else case(state)
   0:if(have_query && latest[16:12]<24 && (!published_valid || latest!=published_descriptor))begin
    job<=latest;job_angle<=latest[16:12];lx<=latest[11:6];ly<=latest[5:0];
    work_bank<=!published_bank;index<=0;wait_count<=0;state<=1;
   end
   1:if(wait_count==2)begin kernel_material<=material;wait_count<=0;state<=2;end else wait_count<=wait_count+1'b1;
   // Input, normal, products, dot, clip, diffuse, composite and exposure.
   // Hold the entry until the complete registered reference pipeline settles.
   2:if(wait_count==12)begin state<=3;wait_count<=0;end else wait_count<=wait_count+1'b1;
   3:if(index==383)state<=4;else begin index<=index+1'b1;wait_count<=0;state<=1;end
   // Publication cannot change the bank or descriptor during any SPI packet.
   4:if(!active_sync && !active_meta && !packet_active)begin
    published_bank<=work_bank;published_descriptor<=job;published_valid<=1;state<=0;
   end
   default:state<=0;
  endcase
endmodule

module photo_relief_tables_a(
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
 reg previous_enable;reg [7:0] owner;reg [6:0] request_sequence;
 reg [16:0] previous_parameters;
 wire [16:0] parameters={desired_angle,desired_light_x,desired_light_y};
 assign request_descriptor={owner,request_sequence,parameters};
 reg [31:0] recent0,recent1,recent2;
 reg [2:0] recent_valid;
 reg [31:0] active_descriptor,pending_descriptor,candidate_descriptor;
 reg receiving,accepted,failed,pending_valid,write_bank;
 reg [8:0] expected_index;
 assign display_angle=active_descriptor[16:12];
 assign display_light_x=active_descriptor[11:6];assign display_light_y=active_descriptor[5:0];
 reg mailbox_request;reg [8:0] mailbox_address;reg [31:0] mailbox_data;
 reg mailbox_ack;(* async_reg="true" *)reg [2:0] ack_sync,mail_sync;
 (* async_reg="true" *)reg [8:0] address_meta,address_sync;
 (* async_reg="true" *)reg [31:0] data_meta,data_sync;
 wire mailbox_busy=ack_sync[2]!=mailbox_request;
 assign available=enable && !receiving && !pending_valid && !mailbox_busy;
 assign palette_we=mem_enable && mail_sync[2]!=mailbox_ack;
 assign palette_wa=address_sync;assign palette_wd=data_sync;
 always @(posedge mem_clk or posedge mem_rst)
  if(mem_rst)begin mail_sync<=0;address_meta<=0;address_sync<=0;data_meta<=0;data_sync<=0;mailbox_ack<=0;end
  else begin
   mail_sync<={mail_sync[1:0],mailbox_request};address_meta<=mailbox_address;address_sync<=address_meta;
   data_meta<=mailbox_data;data_sync<=data_meta;
   // ACK on the same edge as the RAM write (or discard after scene exit).
   if(mail_sync[2]!=mailbox_ack)mailbox_ack<=mail_sync[2];
  end
 always @(posedge clk or posedge rst)
  if(rst)ack_sync<=0;else ack_sync<={ack_sync[1:0],mailbox_ack};
 wire matched=recent_valid[0] && word_data==recent0 || recent_valid[1] && word_data==recent1 || recent_valid[2] && word_data==recent2;
 wire data_ok=enable && receiving && accepted && !failed && word_valid && word_index==expected_index;
 assign wall_we=data_ok && word_index>=257 && word_index<=384;
 assign wall_wa={write_bank,(word_index[6:0]-7'd1)};
 assign wall_wd=word_data[31:8];
 always @(posedge clk or posedge rst)
  if(rst)begin previous_enable<=0;owner<=0;request_sequence<=0;previous_parameters<=0;
   recent0<=0;recent1<=0;recent2<=0;recent_valid<=0;active_descriptor<=0;pending_descriptor<=0;candidate_descriptor<=0;
   active_valid<=0;active_bank<=0;receiving<=0;accepted<=0;failed<=0;pending_valid<=0;write_bank<=1;expected_index<=0;
   mailbox_request<=0;mailbox_address<=0;mailbox_data<=0;rejected<=0;end
  else begin
   previous_enable<=enable;
   if(enable!=previous_enable)begin owner<=owner+1'b1;request_sequence<=0;recent_valid<=0;active_valid<=0;
    pending_valid<=0;receiving<=0;accepted<=0;failed<=0;rejected<=0;end
   else if(enable)begin
    if(parameters!=previous_parameters)begin request_sequence<=request_sequence+1'b1;previous_parameters<=parameters;end
    if(request_sent)begin recent0<=sent_descriptor;recent1<=recent0;recent2<=recent1;recent_valid<={recent_valid[1:0],1'b1};end
    if(frame_tick && pending_valid)begin active_descriptor<=pending_descriptor;active_bank<=write_bank;active_valid<=1;pending_valid<=0;end
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
    if(finish_packet)begin
     receiving<=0;
     if(receiving && accepted && !failed && commit_packet && expected_index==385 && !mailbox_busy)begin pending_valid<=1;pending_descriptor<=candidate_descriptor;end
     else rejected<=1;
    end
   end
  end
endmodule
