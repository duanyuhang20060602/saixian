`timescale 1ns/1ps
module tb;
reg clk=0;always #5 clk=~clk;
reg rst=1,rv=0,we=0;reg[9:0] ra=0;reg[10:0] wa=0;reg[31:0] wd=0;
wire[63:0] got,expected;
water_native_cache dut(clk,ra,wa,we,wd,got,rst,rv);
cache_reference reference(clk,ra,wa,we,wd,expected);
reg qv=0;integer n=0,cycle=0,i,j,k,row,pass,seed=489;
always @(posedge clk)begin
 qv<=rv&&!rst;#1;
 if(qv)begin end
end
// Read accepted on edge C0 must equal the reference after edge C1.
reg d0=0,d1=0;always @(posedge clk)begin
 d0<=rv&&!rst;d1<=d0&&!rst;#2;
 if(d1)begin
  if(got!==expected)$fatal(1,"cache mismatch cycle%0d ra%0d got%h expected%h",cycle,ra,got,expected);
  n=n+1;
 end
 cycle=cycle+1;
end
function[31:0] value;input integer a,p;begin value=(32'h9e3779b9*a)^(32'h7126a9c3*p)^(a<<16);end endfunction
task fill;input integer start,count,p;begin
 for(i=start;i<start+count;i=i+1)begin @(negedge clk);we=1;wa=i;wd=value(i,p);end
 @(negedge clk);we=0;repeat(5)@(negedge clk);
end endtask
task read_group;input integer a;begin
 @(negedge clk);rv=1;ra=a;
 @(negedge clk);rv=0;ra=$random(seed)%640;
end endtask
initial begin
 repeat(4)@(negedge clk);rst=0;fill(0,1280,0);
 for(pass=0;pass<4;pass=pass+1)for(j=0;j<640;j=j+1)read_group(j);
 // Concurrent opposite-row writes, consecutive SDRAM words and row ownership.
 for(pass=1;pass<5;pass=pass+1)for(row=0;row<2;row=row+1)begin
  fork
   begin fill(row*640,640,pass);end
   begin for(k=0;k<320;k=k+1)read_group((1-row)*320+k);end
  join
  repeat(6)@(negedge clk);
 end
 // Destination half-plane occupies only 320 atomic groups, never tail storage.
 fill(0,640,9);for(j=0;j<320;j=j+1)read_group(j);
 repeat(8)@(negedge clk);$display("PASS packed native cache: %0d atomic 64-bit reads, every entry, opposite-row simultaneous writes, invalid-coordinate changes and half-plane ownership",n);$finish;
end
initial begin #1000000;$fatal(1,"cache timeout");end
endmodule
module cache_reference(input clk,input[9:0] ra,input[10:0] wa,
 input we,input[31:0] wd,output[63:0] rd);
reg[9:0] ra_q;reg[10:0] wa_q;reg we_q;reg[31:0] wd_q;
always @(posedge clk)begin ra_q<=ra;wa_q<=wa;we_q<=we;wd_q<=wd;end
genvar h;
generate for(h=0;h<4;h=h+1)begin:lane
 wire selected=we_q&&(wa_q[0]!=(h/2));
`ifdef WATER_SIM
 reg[15:0] mem[0:2047];reg[15:0] qr;
 always @(posedge clk)begin
  if(selected)mem[{1'b0,wa_q[10:1]}]<=wd_q[(h%2)*16+:16];
  qr<=mem[{1'b0,ra_q}];
 end
 assign rd[h*16+:16]=qr;
`else
 // 640 used addresses fit 1024x16. RAM9K lanes cost 72Kbits rather than
 // wasting four 32K macros on this 40Kbit cache; eight RAM9K are available.
 EG_LOGIC_BRAM #(.DATA_WIDTH_A(16),.ADDR_WIDTH_A(10),.DATA_DEPTH_A(1024),
  .DATA_WIDTH_B(16),.ADDR_WIDTH_B(10),.DATA_DEPTH_B(1024),.BYTE_ENABLE(0),
  .MODE("PDPW"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),
  .WRITEMODE_A("NORMAL"),.WRITEMODE_B("NORMAL"),.RESETMODE("SYNC"),.IMPLEMENT("9K")) ram(
  .clka(clk),.rsta(1'b0),.cea(1'b1),.wea(selected),.ocea(1'b1),.bea(1'b0),
  .addra(wa_q[10:1]),.dia(wd_q[(h%2)*16+:16]),.doa(),
  .clkb(clk),.rstb(1'b0),.ceb(1'b1),.web(1'b0),.oceb(1'b1),.beb(1'b0),
  .addrb(ra_q),.dib(16'd0),.dob(rd[h*16+:16]));
`endif
end endgenerate
endmodule
