`timescale 1ns/1ps
module tb_shared_media_fifo;
reg sdclk=0,mclk=0,vclk=0;
always #5 sdclk=~sdclk;always #10 mclk=~mclk;always #6.667 vclk=~vclk;
reg rst=1,mode=0,uwe=0,upop=0,vwe=0,vpop=0,photo_re=0;
reg [31:0] udata=0,vdata=0;
wire [31:0] uhead,vhead;wire [8:0] uc,vc;wire ue,ve,full;
wire [31:0] photo_data,ref_data;
wire ref_empty;
frame_read_write #(.ENABLE_DELTA(1)) dut(
 .rst(rst),.mem_clk(mclk),.Sdr_init_done(1'b0),.Sdr_init_ref_vld(1'b0),.Sdr_busy(1'b0),
 .Sdr_rd_en(vwe),.Sdr_rd_dout(vdata),.read_clk(vclk),.read_req(1'b0),.read_en(photo_re),
 .read_data(photo_data),.read_fifo_empty(ve),.write_clk(sdclk),.write_req(1'b0),
 .write_en(1'b0),.write_data(32'd0),.write_fifo_full(full),
 .delta_mode(mode),.delta_upload_reset(rst),.delta_upload_we(uwe),.delta_upload_data(udata),
 .delta_upload_pop(upop),.delta_upload_head(uhead),.delta_upload_count(uc),.delta_upload_empty(ue),
 .delta_video_reset(rst),.delta_video_push(vwe),.delta_video_data(vdata),
 .delta_video_pop(vpop),.delta_video_head(vhead),.delta_video_count(vc));
rfifo_32_32_512 reference(.rst(rst|dut.read_fifo_aclr),.clkw(mclk),.clkr(vclk),
 .we(vwe),.di(vdata),.re(photo_re&&!ref_empty),.dout(ref_data),.empty_flag(ref_empty));
always @(posedge vclk)if(!rst && !mode)begin
 #1;if(ve!==ref_empty || photo_data!==ref_data)$fatal(1,"photo FIFO latency/data changed");
end
task reset;begin rst=1;repeat(12)@(negedge mclk);rst=0;repeat(12)@(negedge mclk);end endtask
integer i,chunk,pass;
initial begin
 reset;
 // Original synchronous-pop path, then mode transitions and pointer wraps.
 for(pass=0;pass<3;pass=pass+1)begin
  mode=0;reset;
  for(i=0;i<100;i=i+1)begin @(negedge mclk);vwe=1;vdata=32'h12340000+i;end
  @(negedge mclk);vwe=0;repeat(12)@(negedge vclk);photo_re=1;
  repeat(100)@(negedge vclk);photo_re=0;repeat(8)@(negedge vclk);
  rst=1;mode=1;reset;
  for(chunk=0;chunk<12;chunk=chunk+1)begin
   for(i=0;i<80;i=i+1)begin
    @(negedge sdclk);if(full)$fatal(1,"upload full");uwe=1;udata=chunk*80+i;
   end
   @(negedge sdclk);uwe=0;repeat(12)@(negedge mclk);
   for(i=0;i<80;i=i+1)begin
    if(ue || uhead!==chunk*80+i)$fatal(1,"shared upload FIFO mismatch %d",chunk*80+i);
    upop=1;@(negedge mclk);
   end
   upop=0;repeat(12)@(negedge mclk);
   for(i=0;i<80;i=i+1)begin @(negedge mclk);vwe=1;vdata=32'hABCD0000+chunk*80+i;end
   @(negedge mclk);vwe=0;repeat(12)@(negedge vclk);
   for(i=0;i<80;i=i+1)begin
    if(ve || vhead!==(32'hABCD0000+chunk*80+i))$fatal(1,"shared video show-ahead mismatch %d",chunk*80+i);
    vpop=1;@(negedge vclk);
   end
   vpop=0;repeat(12)@(negedge vclk);
  end
 end
 $display("PASS shared photo/upload/video FIFOs: original photo latency; three mode cycles; 960 words per cycle; async clocks/pointer wraps");$finish;
end
initial begin #2000000;$fatal(1,"FIFO timeout");end
endmodule
