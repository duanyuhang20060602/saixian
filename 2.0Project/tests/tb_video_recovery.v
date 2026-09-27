`timescale 1ns/1ps
module tb_video_recovery;
reg clk=0; always #5 clk=~clk;
reg rst=1, hs=0, vs=0, de=0, empty=0, valid=1;
reg [31:0] data=32'hF80007E0;
wire re, ho, vo, deo, fault;
wire [23:0] rgb;
video_delay dut(.video_clk(clk),.rst(rst),.read_en(re),.read_data(data),
 .read_empty(empty),.display_valid(valid),.underflow_latched(fault),
 .hs(hs),.vs(vs),.de(de),.hs_r(ho),.vs_r(vo),.de_r(deo),.vout_data(rgb));
reg [20:0] href=0,vref=0,dref=0;
integer pixels=0;
always @(posedge clk) begin
 if(rst) begin href=0;vref=0;dref=0; end
 else begin href={href[19:0],hs};vref={vref[19:0],vs};dref={dref[19:0],de}; end
 #1;
 if({ho,vo,deo} !== {href[20],vref[20],dref[20]}) $fatal(1,"timing misalignment");
 if(!rst && deo && !fault) begin
  if(rgb !== ((pixels%2==0)?24'hFF0000:24'h00FF00)) $fatal(1,"pair order/RGB alignment");
  pixels=pixels+1;
 end
end
task cycles; input integer n; begin repeat(n) @(negedge clk); end endtask
initial begin
 cycles(3);rst=0;cycles(3);de=1;hs=1;cycles(16);de=0;hs=0;cycles(25);
 if(pixels!=16) $fatal(1,"wrong active pixel count");
 de=1;cycles(21);empty=1;cycles(3);empty=0;cycles(4);
 if(!fault || !dut.frame_fault || re) $fatal(1,"underflow not quarantined");
 if(rgb!==0) $fatal(1,"failed frame not blanked");
 cycles(4);if(re) $fatal(1,"read resumed in failed frame");de=0;cycles(25);
 vs=1;cycles(25);vs=0;cycles(25);
 if(dut.frame_fault || !fault) $fatal(1,"recovery/latch incorrect");
 de=1;cycles(30);if(!re && !dut.req_phase) $fatal(1,"no next-frame reads");
 de=0;cycles(25);if(rgb!==0) $fatal(1,"blanking output nonzero");
 rst=1;cycles(2);if(fault) $fatal(1,"reset did not clear fault");
 $display("PASS RGB pair order, 21-stage timing, injected underflow, frame recovery, reset");$finish;
end
endmodule
