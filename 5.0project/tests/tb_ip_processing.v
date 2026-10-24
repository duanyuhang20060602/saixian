`timescale 1ns/1ps
module tb;
reg clk=0,rst=1,start=0,abort=0,read_req=0,ack=0,source_empty=1,read_en=0,effect_plane=0;
always #5 clk=~clk;
reg [31:0] source_data=0;reg [18:0] settings=0;reg [1:0] gain=1;
wire ar,br,ae,be;wire [31:0] ad,bd;
`define CONNECTIONS .clk(clk),.rst(rst),.start(start),.abort(abort),.read_req(read_req),.effect_plane(effect_plane),.source_ack(ack),.source_empty(source_empty),.source_data(source_data),.settings_state(settings),.image_gain(gain),.read_en(read_en)
photo_b_processing #(.FRAME_WORDS(6400)) dut(`CONNECTIONS,.source_read(ar),.empty(ae),.data(ad));
photo_b_processing_ref #(.FRAME_WORDS(6400)) ref_dut(`CONNECTIONS,.source_read(br),.empty(be),.data(bd));
`undef CONNECTIONS
integer cycle=0,index=0,outputs=0,checks=0,maximum=0;
always @(negedge clk)begin
 cycle=cycle+1;source_empty=cycle%17<3;read_en=cycle%997>=300 && cycle%5!=0;
end
always @(posedge clk)begin
 if(start || abort || rst)begin index=0;outputs=0;end
 else begin
  if(ar!==br || ae!==be)$fatal(1,"processing handshake differs");
  if(ar)begin source_data<={16'(index*373+41),16'(index*107+117)};index=index+1;end
  if(read_en && !ae)outputs=outputs+1;
  if(dut.queued>maximum)maximum=dut.queued;
 end
 #1;
 if(ad!==bd)$fatal(1,"processing pixel word differs at %0d got=%h expected=%h",outputs,ad,bd);
 checks=checks+1;
end
task begin_frame;
 input [18:0] configuration;input aux;
 begin
  @(negedge clk);settings=configuration;effect_plane=aux;start=1;
  @(negedge clk);start=0;read_req=1;ack=1;
  repeat(4)@(negedge clk);read_req=0;ack=0;
 end
endtask
task complete_frame;
 input integer words;
 begin
  wait(outputs==words);repeat(40)@(negedge clk);
  if(!ae || outputs!=words)$fatal(1,"processing queue did not drain");
 end
endtask
initial begin
 repeat(4)@(negedge clk);rst=0;
 begin_frame(19'h0b6d3,0);complete_frame(6400);
 gain=2;begin_frame(19'h123ac,1);complete_frame(3200);
 begin_frame(19'h0f3c5,0);wait(index==100);@(negedge clk);abort=1;@(negedge clk);abort=0;
 gain=3;begin_frame(19'h0d52e,0);complete_frame(6400);
 if(maximum<20)$fatal(1,"queue backpressure insufficient");
 $display("PASS B eRAM pixel queue: RGB565/effect plane/565 restart, 16000 exact output words, backpressure, settings, abort/restart; %0d clocks",checks);$finish;
end
initial begin #300000000;$fatal(1,"processing test timeout state=%0d issued=%0d outputs=%0d credits=%0d",dut.state,dut.issued,outputs,dut.credits);end
endmodule
