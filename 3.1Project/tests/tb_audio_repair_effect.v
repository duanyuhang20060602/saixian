`timescale 1ns/1ps
module tb_audio_repair_effect;
reg clk=0;always #5 clk=~clk;
reg rst=1,clear=0,sv=0,en=0;reg signed [15:0] l=0,r=0;
wire signed [15:0] lo,ro;wire valid;
saixian_audio_repair dut(.clk(clk),.rst(rst),.clear(clear),.sample_valid(sv),.enable(en),.left_in(l),.right_in(r),.left_out(lo),.right_out(ro),.out_valid(valid));
integer n,f,outputs=0;real a;
always @(negedge clk)if(valid)begin $fwrite(f,"%0d %0d %0d\n",outputs,lo,ro);outputs=outputs+1;end
initial begin
 f=$fopen("tests/results/repair_effect.txt","w");
 repeat(5)@(negedge clk);rst=0;
 for(n=0;n<8192;n=n+1)begin
  a=6.283185307179586*n/48000;
  @(negedge clk);en=n>=1024;
  if(n<3072)begin l=$rtoi(12000*$sin(1000*a));r=$rtoi(12000*$sin(8000*a));end
  else if(n<4096)begin l=n==3600 ? 30000:0;r=0;end
  else begin l=10000;r=-10000;end
  sv=1;@(negedge clk);sv=0;repeat(399)@(negedge clk);
 end
 if(outputs!=8192)$fatal(1,"repair lost samples %0d",outputs);
 $fclose(f);$display("PASS repair 8192 stereo samples, dry/wet and effect vectors exported");$finish;
end
endmodule
