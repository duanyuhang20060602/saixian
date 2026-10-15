`timescale 1ns/1ps
module tb_dlt_reader;
reg clk=0;always #5 clk=~clk;
reg rst=1,start=0,valid=0,last=0;reg [7:0] data=0;
wire req,ready,done,wr,pv;wire [31:0] sector;wire [23:0] pixel;wire [3:0] error;
reg [7:0] bytes[0:1453567];reg [31:0] expected[0:460799];
reg [2:0] ack=0;integer cycle=0,count=0,i,s;
wire full=cycle%997>=970;
// Speed only output pacing up for exhaustive logical pixel checks. Hardware
// retains PIXEL_GAP=16; its paced write mapping is tested separately.
photo_dlt_reader #(.PIXEL_GAP(1)) dut(clk,rst,start,32'd0,ready,done,error,wr,ack[2],full,pv,pixel,req,sector,valid,data,last);
function [23:0] expand;input [15:0] p;begin expand={p[15:11],p[15:13],p[10:5],p[10:9],p[4:0],p[4:2]};end endfunction
wire w565,w888,a565,a888;wire [31:0] d565,d888;
photo_color_pack p565(clk,rst,wr,1'b0,pv,pixel,w565,d565,a565);
photo_color_pack p888(clk,rst,wr,1'b1,pv,pixel,w888,d888,a888);
integer n565=0,n888=0,j;reg [31:0] target;reg [23:0] p0,p1,p2,p3;
function [23:0] at;input integer n;begin at=expand(n[0] ? expected[n/2][31:16]:expected[n/2][15:0]);end endfunction
always @(posedge clk)begin ack<={ack[1:0],wr};cycle<=cycle+1;end
always @(negedge clk)begin
 if(error)$fatal(1,"original DLT rejected error=%0d state=%0d",error,dut.state);
 if(pv)begin
  if(pixel!==at(count))$fatal(1,"DLT pixel/tag mismatch %0d got=%h expected=%h",count,pixel,at(count));
  count=count+1;
 end
 if(w565)begin
  if(d565!=={expected[n565][15:0],expected[n565][31:16]})$fatal(1,"DLT RGB565 packing/order");n565=n565+1;
 end
 if(w888)begin
  j=(n888/3)*4;p0=at(j);p1=at(j+1);p2=at(j+2);p3=at(j+3);
  case(n888%3)0:target={p0,p1[23:16]};1:target={p1[15:0],p2[23:8]};2:target={p2[7:0],p3};endcase
  if(d888!==target)$fatal(1,"DLT RGB888 packing/order");n888=n888+1;
 end
end
initial forever begin
 wait(req);s=sector;
 for(i=0;i<512;i=i+1)begin @(negedge clk);data=bytes[s*512+i];valid=1;end
 @(negedge clk);valid=0;last=1;@(negedge clk);last=0;wait(!req);
end
initial begin
 $readmemh("tests/results/dlt_bytes.hex",bytes);$readmemh("tests/results/dlt_frame.hex",expected);
 repeat(5)@(negedge clk);rst=0;start=1;@(negedge clk);start=0;
 wait(done);repeat(10)@(negedge clk);
 if(count!=921600 || n565!=460800 || n888!=691200 || !a565 || !a888)$fatal(1,"DLT incomplete raster");
 $display("PASS original AWARD720.DLT NOCRC, 921600 exact top-down pixels/tags, RGB565/RGB888 packing, output stalls");$finish;
end
initial begin #200000000;$fatal(1,"DLT timeout count=%0d state=%0d sector=%0d",count,dut.state,sector);end
endmodule
