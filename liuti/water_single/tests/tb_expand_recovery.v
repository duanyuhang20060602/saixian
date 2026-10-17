module tb;
reg clk=0;always #5 clk=~clk;reg rst=1,de=0,vs=0,empty=1;
wire re,od,ov,oh,fault;wire[23:0] rgb;reg checking=0;integer count=0,i;
water_expand dut(.video_clk(clk),.rst(rst),.read_en(re),.read_data(32'hffffffff),.read_empty(empty),.display_valid(1'b1),
 .underflow_latched(fault),.hs(1'b0),.vs(vs),.de(de),.hs_r(oh),.vs_r(ov),.de_r(od),.vout_data(rgb));
always @(posedge clk)begin #1;
 if(od&&checking)begin
  if(rgb!==24'hffffff)$fatal(1,"scanout did not recover at VS boundary");count=count+1;
 end
end
initial begin
 repeat(8)@(negedge clk);rst=0;de=1;repeat(64)@(negedge clk);de=0;repeat(30)@(negedge clk);
 if(!fault||!dut.frame_fault)$fatal(1,"empty source was not latched");
 empty=0;vs=1;repeat(32)@(negedge clk);vs=0;repeat(32)@(negedge clk);
 if(dut.frame_fault||!fault)$fatal(1,"VS recovery/sticky status");
 checking=1;de=1;repeat(1280)@(negedge clk);de=0;repeat(30)@(negedge clk);
 if(count!=1280)$fatal(1,"recover pixel count %0d",count);
 $display("PASS interpolator underflow latching, VS-boundary recovery, sticky diagnostic and complete recovered row");$finish;
end
initial begin #20000;$fatal(1,"recovery timeout");end
endmodule
