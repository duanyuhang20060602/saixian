`timescale 1ns/1ps
module tb;
reg clk=0,rst=1,request=0;always #5 clk=~clk;
reg[31:0] address=2209;wire valid,finish;wire[7:0] data;wire[3:0] error;
wire read;wire[31:0] sector;reg bv=0,ended=0;reg[7:0] b=0;
photo_font_fat #(.HZ(1000000),.ADDR_BITS(27)) dut(clk,rst,1'b1,request,address,valid,data,finish,error,read,sector,bv,b,ended);
reg[31:0] lbas[0:2047];reg[7:0] blocks[0:1048575],expected[0:8191];
reg[31:0] requests[0:15];integer sectors,nrequests,want_error;
integer st=0,pos=0,base=0,i,j,matched,req=0,received=0,requests_seen=0;
always @(posedge clk)begin
 bv<=0;ended<=0;
 if(read)begin
 if(st!=0)$fatal(1,"overlapping physical sector read");
 matched=-1;for(j=0;j<sectors;j=j+1)if(lbas[j]==sector)matched=j;
 if(matched<0)$fatal(1,"unexpected/out-of-range LBA %d",sector);
 base<=matched*512;pos<=0;st<=1;requests_seen=requests_seen+1;
 end
 if(st==1)begin bv<=1;b<=blocks[base+pos];if(pos==511)st<=2;else pos<=pos+1;end
 if(st==2)st<=3;
 if(st==3)begin ended<=1;st<=0;end
 if(valid)begin
 if(want_error!=0)$fatal(1,"invalid filesystem produced file bytes");
 if(data!==expected[req*512+received])$fatal(1,"file byte mismatch request=%d byte=%d got=%h expected=%h",req,received,data,expected[req*512+received]);
 received=received+1;
 end
end
initial begin
 if(!$value$plusargs("sectors=%d",sectors))$fatal;
 if(!$value$plusargs("requests=%d",nrequests))$fatal;
 if(!$value$plusargs("error=%d",want_error))$fatal;
 $readmemh("lbas.hex",lbas,0,sectors-1);$readmemh("blocks.hex",blocks,0,sectors*512-1);
 if(nrequests>0)begin $readmemh("requests.hex",requests,0,nrequests-1);$readmemh("expected.hex",expected,0,nrequests*512-1);end
 repeat(6)@(negedge clk);rst=0;
 if(want_error!=0)begin
 @(negedge clk);address=2209+requests[0];request=1;@(negedge clk);request=0;wait(error!=0);
 if(error!=want_error)$fatal(1,"wrong rejection %d",error);
 $display("PASS rejected invalid/missing FAT font, error=%d, physical reads=%d",error,requests_seen);$finish;
 end
 for(i=0;i<nrequests;i=i+1)begin
 req=i;received=0;@(negedge clk);address=2209+requests[i];request=1;@(negedge clk);request=0;
 wait(finish);@(negedge clk);if(received!=512)$fatal(1,"wrong output length");repeat(4)@(negedge clk);
 end
 $display("PASS fragmented FAT font: %d independent sectors, %d bytes, %d physical reads",nrequests,nrequests*512,requests_seen);$finish;
end
initial begin #100000000;$fatal(1,"FAT simulation timeout");end
endmodule
