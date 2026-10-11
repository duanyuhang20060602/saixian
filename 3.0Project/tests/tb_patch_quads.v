`timescale 1ns/1ps
module tb_patch_quads;
reg clk=0;always #10 clk=~clk;
reg rst=1,valid=0,visible=0;reg [20:0] target=0;reg [31:0] value=0;
wire rd,wr,ready,drained;wire [20:0] ra,wa;wire [31:0] wd;wire [3:0] mask,error;
reg [31:0] ram[0:230399],golden[0:230399];
integer i,j,b,beats=0,live=0,cycle=0,requests=0;reg previous_wr=0;
reg [20:0] previous_address;reg [31:0] seed=32'h71935428;
wire refreshing=cycle%31==0 && dut.state==0;
delta_memory dut(.clk(clk),.rst(rst),.init(1'b1),.refreshing(refreshing),.busy(rd||wr),
 .app_rd(rd),.rd_addr(ra),.rd_valid(1'b0),.rd_data(32'd0),.app_wr(wr),.wr_addr(wa),.wr_data(wd),
 .upload_done(1'b0),.file_words(21'd0),.up_empty(1'b1),.up_count(9'd0),.up_data(32'd0),.up_pop(),.cache_ready(),
 .frame_toggle(1'b0),.display_valid(visible),.active_slot(1'b0),.video_reset(),.video_push(),.video_data(),.video_count(9'd0),
 .stream_start(1'b0),.stream_offset(21'd0),.stream_words(21'd0),.stream_ack(),.stream_reset(),.cmd_push(),.cmd_data(),.cmd_count(9'd0),
 .patch_valid(valid),.patch_addr(target),.patch_data(value),.patch_ready(ready),.error(error),.idle(),.payload_crc(32'd0),.debug_data()
`ifndef LEGACY_MEMORY
 ,.wr_dm(mask),.patch_drained(drained)
`endif
 );
`ifdef LEGACY_MEMORY
assign mask=4'd0;
assign drained=ready;
`endif
always @(posedge clk)begin
 if(rst)begin previous_wr<=0;cycle<=0;end
 else begin
  cycle<=cycle+1;
  if(wr)begin
   if(refreshing)$fatal(1,"write during refresh");
   if(!previous_wr)begin
    if(wa[1:0]!=0)$fatal(1,"four-word write start is unaligned");
    beats=1;
   end else begin
    if(wa!=previous_address+1)$fatal(1,"four-word group address jumped");
    beats=beats+1;
   end
   if(mask!=0 && mask!=15)$fatal(1,"partial-byte mask on a full RGB565 pair");
   if(mask==0)begin
    live=live+1;if(wa!=target || wd!==value)$fatal(1,"unmasked wrong word");
   end
   for(b=0;b<4;b=b+1)if(!mask[b])ram[wa][b*8+:8]<=wd[b*8+:8];
   previous_address<=wa;
  end
  if(previous_wr && !wr && beats!=4)$fatal(1,"four-word patch requires four beats, got %d",beats);
  previous_wr<=wr;
 end
end
task patch;input [20:0] address;input [31:0] data;
 begin
  @(negedge clk);target=address;value=data;valid=1;beats=0;live=0;
  @(posedge clk);while(!ready && !error)@(posedge clk);
  @(negedge clk);valid=0;wait(drained || error);@(negedge clk);
  if(error || beats!=4 || live!=1)$fatal(1,"patch ack before a complete masked four-word write");
  golden[address]=data;repeat(3)@(negedge clk);
  for(j=0;j<4;j=j+1)if(ram[(address/4)*4+j]!==golden[(address/4)*4+j])$fatal(1,"neighbor overwritten");
  requests=requests+1;
 end
endtask
task stream_quad;input [20:0] base;
 integer lane;
 begin
  @(negedge clk);target=base;value=32'h78563412;valid=1;beats=0;live=0;
  for(lane=0;lane<4;lane=lane+1)begin
   @(posedge clk);while(!ready && !error)@(posedge clk);
   golden[target]=value;
   @(negedge clk);target=target+1;value=value+32'h1020304;
  end
  valid=0;wait(drained || error);@(negedge clk);
  if(error || beats!=4 || live!=4)$fatal(1,"four consecutive patches not coalesced into one transaction");
  requests=requests+4;
 end
endtask
initial begin
 for(i=0;i<230400;i=i+1)begin ram[i]=32'hc5b40000^i;golden[i]=ram[i];end
 repeat(5)@(negedge clk);rst=0;@(negedge clk);dut.cache_ready=1;
 for(i=0;i<8;i=i+1)patch(i,32'hfac00000^i);
 patch(115199,32'h12345678);patch(115200,32'habcdef01);patch(230399,32'hdeadbeef);
 for(i=0;i<96;i=i+1)begin seed=seed*32'd1664525+32'd1013904223;patch(seed%230400,seed);end
 stream_quad(256);
 for(i=0;i<230400;i=i+1)if(ram[i]!==golden[i])$fatal(1,"unexpected global frame-buffer mutation");
 @(negedge clk);visible=1;target=0;valid=1;wait(error);@(negedge clk);
 if(error!=7 || wr)$fatal(1,"active frame write was not rejected");
 $display("PASS quad patches: %d words, all lanes/boundaries/refresh; aligned four-beat masked patches, four contiguous words coalesced, drain before completion, neighbors intact, active-frame protection",requests);$finish;
end
initial begin #1000000;$fatal(1,"quad patch timeout");end
endmodule
