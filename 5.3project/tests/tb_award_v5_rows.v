`timescale 1ns/1ps
module tb;
reg mc=0,vc=0,rst=1;always #10 mc=~mc;always #6.666667 vc=~vc;
reg [31:0] sparse[0:230399],raw[0:326399];
wire req,ack,valid,claim,rd;wire [20:0] address,ra;wire [31:0] data;
wire [3:0] error;wire [23:0] rgb;
reg [11:0] pipeline=0;reg [31:0] response[0:11];reg [3:0] launch=0;reg [20:0] base_addr;
integer cycle=0,i,f,y,k,checks=0,jobs=0;reg toggle=0;
reg [6:0] job_frame=0,job_row=0;
wire refresh=cycle%389<12 && !claim;wire occupied=cycle%103<20 && !claim;
photo_award_memory bus(.clk(mc),.rst(rst),.enable(1'b1),.init_done(1'b1),.refresh(refresh),
 .busy(|pipeline || launch!=0),.frame_busy(occupied),.request(req),.address(address),.acknowledge(ack),
 .data(data),.valid(valid),.claim(claim),.read_command(rd),.read_address(ra),.response_valid(pipeline[11]),.response(response[11]));
always @(posedge mc)begin
 cycle<=cycle+1;
 pipeline<={pipeline[10:0],rd};
if(rd)begin
 if(refresh || occupied)$fatal(1,"light command overlaps owner/refresh");
 response[0]<=sparse[ra];
end
 for(i=1;i<12;i=i+1)response[i]<=response[i-1];
 if(error)$fatal(1,"sparse row player error %0d",error);
end
photo_spotlight_player dut(.mem_clk(mc),.mem_rst(rst),.enable(!rst),.base(21'd0),
 .stream_start(req),.stream_offset(address),.stream_ack(ack),.data(data),.data_valid(valid),.error(error),
 .video_clk(vc),.video_rst(rst),.display_valid(1'b0),.pause(1'b0),.rgb_in(24'd0),.de_in(1'b0),.vs_in(1'b0),.rgb_out(rgb));
initial begin
 $readmemh("light_tail.hex",sparse);$readmemh("light_raw.hex",raw);
 repeat(8)@(negedge mc);rst=0;
 force dut.request_toggle=toggle;force dut.request_frame=job_frame;force dut.request_row=job_row;force dut.request_initial=1'b0;
 for(f=0;f<120;f=f+1)for(y=0;y<68;y=y+1)begin
  @(negedge mc);job_frame=f;job_row=y;toggle=~toggle;
  wait(dut.done_toggle==toggle);@(negedge mc);
  for(k=0;k<40;k=k+1)begin
   if(dut.row_bank[(y%4)*128+k]!==raw[(f*68+y)*40+k])$fatal(1,"current row mismatch frame=%0d row=%0d word=%0d",f,y,k);
   if(dut.row_bank[(y%4)*128+64+k]!==raw[(((f+1)%120)*68+y)*40+k])$fatal(1,"following row mismatch frame=%0d row=%0d word=%0d",f,y,k);
   checks=checks+2;
  end
  jobs=jobs+1;
 end
 $display("PASS lossless sparse row decode: %0d words, %0d paired rows, all 120 fields, wrap, SDRAM contention and refresh",checks,jobs);$finish;
end
initial begin #1000000000;$fatal(1,"row decode timeout state=%0d bus=%0d",dut.state,bus.state);end
endmodule
