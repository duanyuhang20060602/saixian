`timescale 1ns/1ps
// Native asynchronous upload FIFO, with the production 100/50 MHz rates.
// SDRAM is a ten-cycle response model; the encrypted controller is not tested.
module tb_upload_memory #(parameter EARLY_CAPTURE=0);
reg wclk=0,mclk=0;always #5 wclk=~wclk;always #10 mclk=~mclk;
reg rst=1,inject=0;reg [31:0] words[0:4095],ram[0:234495];reg [31:0] crc;
integer written=0,uploaded=0,tick=0,cycle=0,k;
reg we=0;reg [31:0] di=0;wire full,empty,pop;wire [8:0] count;wire [31:0] head;
wfifo_32_32_512 fifo(.rst(rst),.clkw(wclk),.clkr(mclk),.we(we),.di(di),.re(pop),
 .dout(head),.full_flag(full),.empty_flag(empty),.rdusedw(count),.wrusedw(),.valid(),.afull(),.aempty());
always @(negedge wclk)begin
 if(rst)begin written=0;tick=0;we=0;di=0;end
 else begin
  if(we)written=written+1;
  we=0;tick=tick+1;
  if(written<4096 && tick%32==0 && !full)begin we=1;di=words[written];end
 end
end
reg done_meta=0,done=0;reg [9:0] pending=0;reg [31:0] response[0:9];
wire rd,wr,ready;wire [20:0] ra,wa;wire [31:0] wd;wire [3:0] error;
wire busy=rd || wr || |pending;
// Hold init long enough to accumulate a backlog; periodically defer launches.
wire initialized=cycle>1600;
wire refreshing=cycle%761<8 && dut.state==0 && !busy;
wire [31:0] upload_data=head^(inject && uploaded==128 ? 32'd1 : 32'd0);
wire [31:0] captured_data;
delta_read_capture capture(mclk,rst,response[8],captured_data);
wire [31:0] read_data=EARLY_CAPTURE ? captured_data : response[9];
delta_memory #(.VERIFY_CACHE(1)) dut(mclk,rst,initialized,refreshing,busy,
 rd,ra,pending[9],read_data,wr,wa,wd,done,21'd4096,empty,count,upload_data,pop,ready,
 1'b0,1'b0,1'b0,,,,9'd0,1'b0,21'd0,21'd0,,,,,9'd0,1'b0,21'd0,32'd0,,error,,crc,,,);
always @(posedge mclk)begin
 if(rst)begin cycle<=0;uploaded<=0;pending<=0;done_meta<=0;done<=0;end
 else begin
  cycle<=cycle+1;done_meta<=written==4096;done<=done_meta;
  pending<={pending[8:0],rd};if(rd)response[0]<=ram[ra];
  for(k=1;k<10;k=k+1)response[k]<=response[k-1];
  if(wr)ram[wa]<=wd;
  if(pop)begin
   if(head!==words[uploaded])$fatal(1,"native upload FIFO word mismatch %d got %h expected %h",uploaded,head,words[uploaded]);
   uploaded<=uploaded+1;
  end
  if(wr && dut.owner==2 && wd!==upload_data)$fatal;
 end
end
reg [1023:0] path;
initial begin
 if(!$value$plusargs("package=%s",path) || !$value$plusargs("crc=%h",crc))$fatal;
 $readmemh(path,words);repeat(8)@(negedge mclk);rst=0;
 wait(ready || error);
 if(error || !dut.test_done || uploaded!=4096 || (dut.upload_crc^32'hffffffff)!=crc)$fatal(1,"native upload cache failed %h",error);
 $display("PASS native upload: 100/50 MHz asynchronous FIFO; 4096 exact words across pointer wraps; upload CRC, known-pattern BIST and full cache CRC; deferred launches");
 @(negedge mclk);rst=1;inject=1;repeat(8)@(negedge mclk);rst=0;
 wait(ready || error);
 if(ready || error!=10 || dut.test_started)$fatal(1,"native upload injected corruption not isolated");
 $display("PASS native upload: one-bit corruption after FIFO isolated as E2A before SDRAM BIST");$finish;
end
initial begin #15000000;$fatal(1,"native upload timeout");end
endmodule
