`timescale 1ns/1ps
// Full 1650x750 raster: a complete cache spans several 30-line blanking
// windows, and is exposed only on the following frame boundary.
module tb_thumbnail_blanking;
reg mc=0,pc=0,rst=1;
always #10 mc=~mc;
always #6.666667 pc=~pc;
wire [11:0] x;wire [10:0] y;wire valid;
photo_raster_delay #(.DELAY(26)) raster(.clk(pc),.rst(rst),.x(x),.y(y),.valid(valid));
wire tick=valid && x==0 && y==720;
wire blank=valid && y>=720;
wire req,cancel,done,visible,request,claim,rd;wire [1:0] slot;
wire [11:0] address;wire [20:0] source_address;wire [15:0] data;wire [23:0] rgb;
reg [9:0] responses=0;
integer cycles=0,reads=0,frames=0,shown=0;
wire refresh=cycles%765>=740;
photo_thumbnail_overlay overlay(.clk(pc),.rst(rst),.frame_tick(tick),.enable(1'b1),.cache_valid(1'b1),
 .cache_slot(2'd1),.identity(6'd5),.de(valid && x<1280 && y<720),.x(x),.y(y),.request(req),.slot(slot),
 .cancel(cancel),.done(done),.data(data),.address(address),.visible(visible),.rgb_in(24'h102030),.rgb_out(rgb));
photo_thumbnail_memory memory(.clk(mc),.rst(rst),.init_done(1'b1),.refresh(refresh),
 .busy(1'b0),.frame_busy(1'b0),.allow_access(1'b1),.other_request(1'b0),.request(request),.claim(claim),
 .read_command(rd),.address(source_address),.response_valid(responses[9]),.response(32'hf80007e0),
 .video_clk(pc),.video_request(req),.video_cancel(cancel),.video_blank(blank),.video_slot(slot),
 .video_done(done),.video_address(address),.video_data(data));
always @(posedge mc)begin
 cycles<=cycles+1;responses<={responses[8:0],rd};
 if(rd)begin
  reads<=reads+1;
  if(!blank && !(y==0 && x<64))$fatal(1,"active-video sampling x=%d y=%d",x,y);
 end
end
always @(posedge pc)if(!rst)begin
 if(tick)frames=frames+1;
 #1;
 if(visible && valid && x>=1088 && x<1248 && y>=528 && y<618)begin
  if(rgb!==24'hff0000)$fatal(1,"partial or stale cache shown");
  shown=shown+1;
 end
end
initial begin
 repeat(10)@(negedge mc);rst=0;
 wait(shown==14400);@(negedge pc);
 if(reads!=9216 || frames>4 || frames<3)$fatal(1,"blanking schedule reads=%d frames=%d",reads,frames);
 $display("PASS real 720p blanking: cache across %0d frame boundaries, 9216 source words, 14400 complete preview pixels",frames);$finish;
end
initial begin #90000000;$fatal(1,"blanking timeout reads=%d frames=%d shown=%d",reads,frames,shown);end
endmodule
