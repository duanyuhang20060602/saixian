`timescale 1ns/1ps
module tb #(parameter ENABLE_LINE=720,ENABLE_X=1,FRAMES=5);
reg mc=0,vc=0,rst=1,enable=0;always #10 mc=~mc;always #6.666667 vc=~vc;
integer x=0,y=0,frames=0,cycle=0,i,nonzero=0,jobs=0,max_latency=0,job_cycle=0;
reg [31:0] sparse[0:230399];
reg [11:0] val=0;reg [31:0] rdata[0:11];
reg [6:0] de_pipe=0;reg [4:0] vs_pipe=0;
wire de=x<1280 && y<720,vs=x==0 && y==720;
wire req,ack,dv,claim,re;wire [20:0] addr,ra;wire [31:0] data;wire [3:0] error;
wire [23:0] rgb;wire ode,ovs,initialized;wire [6:0] frame;
always @(negedge vc)if(!rst)begin
 if(x==1649)begin x=0;if(y==749)begin y=0;frames=frames+1;end else y=y+1;end else x=x+1;
 if(frames==0 && y==ENABLE_LINE && x==ENABLE_X)enable=1;
end
always @(posedge vc)begin
 de_pipe<={de_pipe[5:0],de};vs_pipe<={vs_pipe[3:0],vs};
 if(ode && initialized && rgb!=24'h283c50)nonzero=nonzero+1;
 if(!rst && dut.request_pending && job_cycle==0)job_cycle=cycle;
 if(!rst && !dut.request_pending && job_cycle!=0)begin
  if(cycle-job_cycle>max_latency)max_latency=cycle-job_cycle;job_cycle=0;jobs=jobs+1;
 end
 if(vs && enable)$display("FRAME %0d init=%b ready=%b index=%0d step=%0d error=%h videoerr=%b nz=%0d jobs=%0d",frames,initialized,dut.next_ready,frame,dut.step,error,dut.video_error,nonzero,jobs);
 if(frames==FRAMES)begin
  if(error || dut.video_error || !initialized || frame==0 || nonzero<1000 || jobs<100)$fatal(1,"spotlight did not animate");
  $display("PASS continuous startup at %0d/%0d: frames=%0d jobs=%0d max latency=%0d lit pixels=%0d index=%0d",ENABLE_X,ENABLE_LINE,FRAMES,jobs,max_latency,nonzero,frame);$finish;
 end
end
always @(posedge mc)begin
 cycle<=cycle+1;val<={val[10:0],re};
 if(re)begin
  if(ra<460800 || ra>=691200)$fatal(1,"tail address out of slot %0d",ra);
  rdata[0]<=sparse[ra-460800];
 end
 for(i=1;i<12;i=i+1)rdata[i]<=rdata[i-1];
 if(!rst && error)$fatal(1,"light error=%0d video=%b raster=%0d/%0d player=%0d/%0d ready=%b pending=%b state=%0d word=%0d",error,dut.video_error,x,y,dut.pixel_x,dut.pixel_y,dut.next_ready,dut.request_pending,dut.state,dut.table_word);
end
photo_award_memory bus(.clk(mc),.rst(rst),.enable(enable),.init_done(1'b1),.refresh(cycle%389<9),.busy(|val),.frame_busy(cycle%11<3),
 .request(req),.address(addr),.acknowledge(ack),.data(data),.valid(dv),.claim(claim),.read_command(re),.read_address(ra),.response_valid(val[11]),.response(rdata[11]));
photo_spotlight_player dut(.mem_clk(mc),.mem_rst(rst),.enable(enable),.base(21'd460800),
 .stream_start(req),.stream_offset(addr),.stream_ack(ack),.data(data),.data_valid(dv),.error(error),
 .video_clk(vc),.video_rst(rst || !enable),.display_valid(enable),.pause(1'b0),.rgb_in(24'h283c50),.de_in(de_pipe[6]),.vs_in(vs_pipe[4]),
 .rgb_out(rgb),.de_out(ode),.vs_out(ovs),.frame_index(frame),.initialized(initialized));
initial begin $readmemh("light_tail.hex",sparse);repeat(8)@(negedge mc);rst=0;end
initial begin #120000000;$fatal(1,"timeout");end
endmodule
