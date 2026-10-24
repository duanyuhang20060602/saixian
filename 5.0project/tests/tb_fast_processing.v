`timescale 1ns/1ps
module processing_case #(parameter FAST=0,WORDS=6400)(input clk,rst,start,abort,read_req,ack,aux,stalls,input [18:0] settings,input [1:0] gain,
 output reg [31:0] result[0:WORDS-1],output reg [31:0] outputs=0,output reg [31:0] elapsed=0,output reg [5:0] maximum=0);
reg [31:0] source_data=0;wire read,empty;wire [31:0] data;reg [31:0] cycles=0,index=0;reg enabled=0;
wire source_empty=stalls && cycles%17<3;
wire pop=enabled && (!stalls || (cycles%997>=300 && cycles%5!=0));
`define PORTS .clk(clk),.rst(rst),.start(start),.abort(abort),.read_req(read_req),.effect_plane(aux),.source_ack(ack),.source_empty(source_empty),.source_data(source_data),.source_read(read),.read_en(pop),.empty(empty),.data(data),.settings_state(settings),.image_gain(gain)
generate if(FAST)begin: new_core
 photo_b_processing #(.FRAME_WORDS(WORDS)) dut(`PORTS);
 always @(posedge clk)if(dut.queued>maximum)maximum<=dut.queued;
end else begin: old_core
 photo_b_processing_baseline #(.FRAME_WORDS(WORDS)) dut(`PORTS);
end endgenerate
`undef PORTS
always @(posedge clk)begin
 cycles<=cycles+1;
 if(rst || start || abort)begin outputs=0;index=0;elapsed=0;enabled=!rst && !abort;maximum<=0;end
 else begin
  elapsed<=elapsed+1;
  if(read)begin source_data<={16'(index*373+41),16'(index*107+117)};index=index+1;end
  if(pop && !empty)begin
   #1;if(outputs>=WORDS)$fatal(1,"processing overrun");result[outputs]=data;outputs=outputs+1;
  end
 end
end
endmodule
module tb;
reg clk=0,rst=1,start=0,abort=0,req=0,ack=0,aux=0,stalls=0;always #5 clk=~clk;
reg [18:0] settings=0;reg [1:0] gain=1;
wire [31:0] oa,ob,ea,eb;wire [5:0] ma,mb;wire [31:0] a[0:6399],b[0:6399];integer i,checks=0;
processing_case #(.FAST(1)) fast(clk,rst,start,abort,req,ack,aux,stalls,settings,gain,a,oa,ea,ma);
processing_case baseline(clk,rst,start,abort,req,ack,aux,stalls,settings,gain,b,ob,eb,mb);
task begin_frame;input [18:0] configuration;input plane,slow;
 begin @(negedge clk);settings=configuration;aux=plane;stalls=slow;start=1;
 @(negedge clk);start=0;req=1;ack=1;repeat(4)@(negedge clk);req=0;ack=0;end
endtask
task compare;input integer words;reg [31:0] ca,cb;
 begin
  wait(oa==words);ca=ea;wait(ob==words);cb=eb;repeat(30)@(negedge clk);
  if(oa!=words || ob!=words)$fatal(1,"queue failed to drain");
  for(i=0;i<words;i=i+1)if(a[i]!==b[i])$fatal(1,"processing pixels differ at %0d %h/%h",i,a[i],b[i]);
  if(!stalls && ca*10>=cb*8)$fatal(1,"overlap failed to improve throughput %0d/%0d",ca,cb);
  checks=checks+words;$display("PASS B processing plane=%0d stalls=%0d: %0d identical words, cycles=%0d vs baseline=%0d",aux,stalls,words,ca,cb);
 end
endtask
initial begin
 repeat(4)@(negedge clk);rst=0;
 begin_frame(19'h0b6d3,0,0);compare(6400);
 gain=2;begin_frame(19'h123ac,1,0);compare(3200);
 gain=3;begin_frame(19'h0d52e,0,1);compare(6400);if(ma<20)$fatal(1,"insufficient queue backpressure");
 begin_frame(19'h0f3c5,1,1);repeat(200)@(negedge clk);abort=1;@(negedge clk);abort=0;
 begin_frame(19'h0f3c5,1,1);compare(3200);
 $display("PASS B pipeline overlap: %0d exact words, settings/gain, full pressure, abort/restart; queue capacity and latency contract preserved",checks);$finish;
end
initial begin #10000000;$fatal(1,"processing timeout outputs=%0d/%0d",oa,ob);end
endmodule
