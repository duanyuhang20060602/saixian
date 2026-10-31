`timescale 1ns/1ps
module tb;
reg clk=0,rst=1,valid=0,ending=0;always #5 clk=~clk;
reg [7:0] data=0,records[0:8191];reg [7:0] address=0;
wire ready;wire [4:0] length;wire [31:0] word;
photo_sd_title_store #(.INDEPENDENT_TEXT(1)) dut(clk,rst,valid,data,ending,ready,length,address,word);
integer i,j;
task reset;begin @(negedge clk);rst=1;repeat(3)@(negedge clk);rst=0;end endtask
task sector;input integer base,flip;begin
 for(j=0;j<512;j=j+1)begin
  @(negedge clk);valid=1;data=records[base+j] ^ (j==flip ? 8'h01:8'h00);
  if(j%7==0)begin @(negedge clk);valid=0;end
 end
 @(negedge clk);valid=0;ending=1;@(negedge clk);ending=0;repeat(2)@(negedge clk);
end endtask
task check;input integer base,expected_length;reg [31:0] expected;begin
 if(!ready)$fatal(1,"incomplete title published");
 for(i=0;i<256;i=i+1)begin
  address=i;#1;if(length!=(i<128 ? expected_length:(base==0 ? 6:16)))$fatal(1,"bank length mismatch");repeat(2)@(negedge clk);
  expected={records[base+(i/64)*512+20+(i%64)*4],records[base+(i/64)*512+21+(i%64)*4],
   records[base+(i/64)*512+22+(i%64)*4],records[base+(i/64)*512+23+(i%64)*4]};
  if(word!==expected)$fatal(1,"font word %0d got %h expected %h",i,word,expected);
 end
end endtask
initial begin
 $readmemh("title_records.hex",records);reset;
 sector(0,0);sector(512,-1);sector(1024,-1);sector(1536,-1);if(ready)$fatal(1,"bad magic accepted");reset;
 sector(0,-1);sector(512,-1);sector(1024,-1);if(ready)$fatal(1,"three records became ready");
 sector(1536,27);if(ready)$fatal(1,"bad CRC accepted");sector(1536,-1);check(0,16);
 sector(4096,-1);check(0,16);
 reset;sector(0,-1);sector(2560,-1);sector(3072,-1);sector(3584,-1);if(ready)$fatal(1,"mixed identities accepted");sector(2048,-1);check(2048,3);
 reset;sector(1536,-1);sector(512,-1);sector(1024,-1);sector(0,-1);check(0,16);
 reset;sector(0,-1);sector(0,30);sector(512,-1);sector(1024,-1);sector(1536,-1);if(ready)$fatal(1,"bad replacement retained acceptance");sector(0,-1);check(0,16);
 reset;sector(4096,-1);sector(4608,-1);sector(5120,-1);sector(5632,-1);if(ready)$fatal(1,"invalid version accepted");
 sector(6144,-1);sector(6656,-1);sector(7168,-1);sector(7680,-1);if(ready)$fatal(1,"invalid length accepted");
 $display("PASS 4-sector independent text CRC, missing/corrupt/reordered/mixed records, all 512 rows and separate lengths");$finish;
end
initial begin #1000000;$fatal(1,"title store timeout");end
endmodule
