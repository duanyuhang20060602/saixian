`timescale 1ns/1ps
// Exercise the production photo reader and TF arbiter with delayed SDRAM
// responses, refresh stalls, and frame events while TF is hidden/cached.
module tb_static_bus_ownership;
reg clk=0,rst=1;always #10 clk=~clk;
reg request=0,frame=0,start=0,refresh=0;
wire photo_rd,claim,ack,clear,tf_rd,tf_wr,idle,video_reset,stream_ack;
wire local_clear;
wire photo_grant=idle || local_clear;
`ifdef PRE_FIX
assign local_clear=1'b0;
`endif
wire [20:0] photo_addr;
wire [3:0] error;
reg [47:0] pending=0;
integer cycle=0,occupancy=0,issued=0,received=0,clears=0,streams=0;
wire physical_busy=|pending;
wire response=pending[47];
frame_fifo_read photo(.rst(rst),.mem_clk(clk),.Sdr_init_done(1'b1),
 .Sdr_init_ref_vld(refresh),.Sdr_busy(physical_busy),.Sdr_rd_en(response && photo_grant),
 .App_wr_busy(1'b0),.App_rd_en(photo_rd),.App_rd_addr(photo_addr),
 .read_req(request),.read_req_ack(ack),.read_addr_0(21'd0),.read_addr_1(21'd460800),
 .read_addr_2(21'd921600),.read_addr_3(21'd0),.read_addr_index(2'd0),.read_len(21'd460800),
 .slide_active(1'b0),.slide_old_index(2'd0),.slide_new_index(2'd0),.slide_offset(11'd0),
 .slide_right(1'b0),.transition_mode(3'd0),.buffer0_vga(1'b0),.buffer1_vga(1'b0),
 .fifo_aclr(clear),.wrusedw(occupancy[8:0]),
 .background_busy(!photo_grant || physical_busy || refresh),.bus_claim(claim));
delta_memory #(.RUN_BUS_TEST(0)) tf(.clk(clk),.rst(rst),.init(1'b1),
 .refreshing(refresh),.busy(physical_busy || (idle && claim)),
 .app_rd(tf_rd),.app_wr(tf_wr),.rd_valid(1'b0),.rd_data(32'd0),
 .upload_done(1'b1),.file_words(21'd0),.up_empty(1'b1),.up_count(9'd0),.up_data(32'd0),
 .frame_toggle(frame),.display_valid(1'b0),.active_slot(1'b0),.video_reset(video_reset),.video_count(9'd0),
 .stream_start(start),.stream_offset(21'd0),.stream_words(21'd0),.stream_ack(stream_ack),
 .cmd_count(9'd0),.patch_valid(1'b0),.patch_addr(21'd0),.patch_data(32'd0),
 .payload_crc(32'd0),.error(error),.idle(idle)
`ifndef PRE_FIX
 ,.local_clear(local_clear)
`endif
);
always @(posedge clk) begin
 if(rst)pending<=0;
 else begin
  pending<={pending[46:0],photo_rd};
  if(photo_rd)begin
   if(!photo_grant)$fatal(1,"TF stole an issued photo read");
   issued=issued+1;
  end
  if(response)begin
   if(!photo_grant)$fatal(1,"TF stole a delayed photo response: cycle %0d, state %0d",cycle,tf.state);
   received=received+1;
  end
  if(error || tf_rd || tf_wr)$fatal(1,"hidden cache issued unexpected traffic");
 end
end
always @(negedge clk)if(!rst)begin
 cycle=cycle+1;
 if(clear)occupancy=0;
 else occupancy=occupancy+(response ? 1 : 0)-((cycle%3==0 && occupancy>0) ? 1 : 0);
 if(occupancy>=512)$fatal(1,"photo FIFO overflow");
 // Relatively prime event periods cover all alignments within a photo burst.
 if(cycle%251==19)frame=~frame;
 refresh=(cycle%765)>=740;
 if(cycle%997==73)start=1;
 if(stream_ack)begin start=0;streams=streams+1;end
 if(video_reset)clears=clears+1;
end
initial begin
 repeat(4)@(negedge clk);rst=0;request=1;
 wait(ack);@(negedge clk);request=0;
 repeat(300000)@(negedge clk);
 if(received<90000 || clears<1000 || streams<200)$fatal(1,"insufficient progress: %d %d %d",received,clears,streams);
 $display("PASS static photo bus ownership: %0d reads/%0d delayed responses, %0d clear cycles/%0d command handshakes, refresh stalls, hidden cached TF",issued,received,clears,streams);
 $finish;
end
initial begin #7000000;$fatal(1,"ownership timeout");end
endmodule
