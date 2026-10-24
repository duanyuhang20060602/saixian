`timescale 1ns/1ps
module tb;
reg clk=0,rst=1,valid=0;reg[5:0] index=0;reg[7:0] data=0;
wire ok,reference_ok;wire[31:0] bytes,crc,reference_bytes,reference_crc;
photo_dlt_header dut(clk,rst,valid,index,data,ok,bytes,crc);
photo_dlt_header_5_5 reference(clk,rst,valid,index,data,reference_ok,reference_bytes,reference_crc);
always #5 clk=~clk;
integer n,j,checked=0;reg[351:0] header;
task check;begin @(negedge clk);if({ok,bytes,crc}!=={reference_ok,reference_bytes,reference_crc})$fatal(1,"header cycle mismatch %0d index=%0d",checked,index);checked=checked+1;end endtask
initial begin
 repeat(3)check();rst=0;
 header=0;header[63:0]=64'h353030544c445853;header[79:64]=5;header[95:80]=512;
 header[111:96]=1280;header[127:112]=720;header[159:128]=1;header[191:160]=2048;
 header[223:192]=460800;header[255:224]=1;header[287:256]=32;header[319:288]=32'h89abcdef;header[351:320]=2;
 for(n=0;n<200;n=n+1)begin
  rst=1;check();rst=0;
  case(n%8)0:header[191:160]=2048;1:header[191:160]=4702208;
   2:header[191:160]=1536;3:header[191:160]=4702720;
   4:header[191:160]=2049;5:header[191:160]=32'hffffffff;
   6:header[191:160]=4096;7:header[191:160]=0;endcase
  // Reverse writes verify that no sequential-byte-order assumption exists.
  for(j=43;j>=0;j=j-1)begin valid=1;index=j;data=header[j*8+:8];check();end
  valid=0;repeat(3)check();
  if(n%8==0 || n%8==1 || n%8==6)begin
   if(!ok)$fatal(1,"valid header rejected");
   for(j=0;j<44;j=j+1)if(!(j>=20 && j<24) && !(j>=36 && j<40))begin
    valid=1;index=j;data=header[j*8+:8]^8'h01;check();valid=0;repeat(2)check();
    if(ok)$fatal(1,"bad constant byte accepted %0d",j);
    valid=1;data=header[j*8+:8];check();valid=0;repeat(2)check();
    if(!ok)$fatal(1,"restored constant byte rejected %0d",j);
   end
  end
 end
 for(n=0;n<20000;n=n+1)begin
  index=$random;data=$random;valid=($random & 3)!=0;rst=(n%997)==0;check();
 end
 $display("PASS %0d cycle-exact header checks: reverse/partial/repeated writes, every corrupted constant byte, file-size bounds/alignment, CRC payload, ignored indexes and resets",checked);$finish;
end
endmodule
