`timescale 1ns/1ps
module tb_loader;
reg clk=0;always #5 clk=~clk;
reg rst=1,sd_init=0,valid=0,last=0,full=0;reg [7:0] data=0;
wire req,ready,we;wire [31:0] sector,word;wire [20:0] file_words;wire [5:0] frames;
wire [2:0] error;wire [3:0] state;
wire [31:0] payload_crc;
delta_loader #(.WIDTH(1280),.HEIGHT(720),.FORMAT_VERSION(4),.CLOCK_HZ(1000),.MAX_SECTOR(8000)) dut(clk,rst,sd_init,req,sector,valid,data,last,full,
 we,word,ready,file_words,frames,error,state,payload_crc);
reg [7:0] bytes[0:3238399];reg [1023:0] path;
integer i,mode,k,offset,written=0,transactions=0;
always @(posedge clk)if(!rst && we)begin
 if(word!=={bytes[written*4+3],bytes[written*4+2],bytes[written*4+1],bytes[written*4]})begin
  if(mode!=1 || written!=809599)$fatal(1,"upload word mismatch %d",written);
 end
 written=written+1;
end
task reset;
 begin @(negedge clk);rst=1;valid=0;last=0;full=0;sd_init=0;written=0;transactions=0;
 repeat(4)@(negedge clk);rst=0;sd_init=1;end
endtask
task block;
 input integer count;
 begin wait(req);@(negedge clk);transactions=transactions+1;offset=(sector-3)*512;
 for(k=0;k<count;k=k+1)begin
  valid=1;data=sector<3 ? 0 : bytes[offset+k];
  if(mode==1 && sector==6327 && k==511)data=data^1;
  @(negedge clk);
 end
 valid=0;last=1;@(negedge clk);last=0;repeat(3)@(negedge clk);
 end
endtask
initial begin
 if(!$value$plusargs("package=%s",path))$fatal;$readmemh(path,bytes);
 mode=0;reset;while(!ready && error==0)block(512);
 if(!ready || written!=809600 || file_words!=809600 || frames!=1)$fatal(1,"load failed %d words=%d",error,written);
 if(payload_crc!=={bytes[39],bytes[38],bytes[37],bytes[36]})$fatal(1,"CRC metadata handed to memory checker is wrong");
 repeat(20)@(negedge clk);if(req || we)$fatal(1,"read continues after preload");
 $display("PASS loader: complete original-action package upload, CRC32, 720p format-4 header and stop after preload");
 mode=1;reset;while(!ready && error==0)block(512);
 if(ready || error!=5)$fatal(1,"corrupt package accepted %d",error);
 mode=2;reset;block(511);if(error!=4 || ready)$fatal(1,"truncated sector accepted");
 reset;wait(req);repeat(11000)@(negedge clk);if(error!=4 || ready || req)$fatal(1,"stall timeout failed");
 $display("PASS loader: CRC corruption, truncated sector, read stall rejected");$finish;
end
initial begin #100000000;$fatal(1,"test timeout");end
endmodule
