`timescale 1ns/1ps
module tb;
reg clk=0;always #5 clk=~clk;reg rst=1,loading=0,scaler_pixel=0,load_start=0;
reg [10:0] stat_x=0;reg [9:0] stat_y=0;reg [12:0] count=0;reg [20:0] sum=0;wire [1:0] result,reference;
production_gain dut(.clk(clk),.rst(rst),.loading(loading),.scaler_pixel(scaler_pixel),.load_start(load_start),.stat_x(stat_x),.stat_y(stat_y),.stat_count(count),.stat_sum(sum),.result(result),.reference(reference));
always @(posedge clk or posedge rst)if(rst)count<=0;else if(loading && scaler_pixel && stat_x[3:0]==0 && stat_y[3:0]==0)count<=count+1'b1;else if(load_start)count<=0;
integer i,j,k,checks=0,wraps=0;reg [31:0] rng=32'h6127def3;
always @(posedge clk)begin #1;if(!rst)begin
 if(dut.stat_count3!==count*3 || dut.stat_count9!==count*9)$fatal(1,"counter multiple changed n=%d",count);
 if(result!==reference)$fatal(1,"gain changed n=%d sum=%d result=%d expected=%d",count,sum,result,reference);
 checks=checks+1;
end end
initial begin
 repeat(5)@(negedge clk);rst=0;
 // Two full count wraps, with all three boundaries and exact equality.
 for(i=0;i<16384;i=i+1)begin
  for(j=0;j<3;j=j+1)for(k=-1;k<=1;k=k+1)begin
   @(negedge clk);loading=0;scaler_pixel=0;sum=count*(j==0 ? 64:j==1 ? 96:144)+k;
  end
  @(negedge clk);loading=1;scaler_pixel=1;stat_x=0;stat_y=0;
  @(negedge clk);loading=0;scaler_pixel=0;if(count==0)wraps=wraps+1;
 end
 for(i=0;i<100000;i=i+1)begin
  @(negedge clk);rng={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
  loading=rng[0];scaler_pixel=rng[1];load_start=rng[7:2]==0;stat_x=rng[8] ? 0:rng[19:9];stat_y=rng[20] ? 0:rng[30:21];sum=rng[20:0];rst=i%5000==4999;
 end
 @(negedge clk);if(wraps!=2)$fatal(1,"missing count wraps");
 $display("PASS exact gain thresholds: %0d same-cycle comparisons, all 8192 counts at all nine boundary values, two wraps, reset/load/sample/hold priority",checks);$finish;
end
endmodule
