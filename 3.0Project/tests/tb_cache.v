`timescale 1ns/1ps
module tb_cache #(parameter EARLY_READ=0,CAPTURE_READ=0,EXPECT_EARLY_FAIL=0);
reg clk=0;always #10 clk=~clk;
reg rst=1,bad=0,bad_up=0,corrupted=0,start=0;integer fault=0;
reg [20:0] off=0,len=0;
reg [31:0] crc;
reg [31:0] package_words[0:511],ram[0:230911];
reg [9:0] pending=0;reg [31:0] response[0:9];
integer uploaded=0,i,j,accepted=0,wanted=0,counter=0,bursts=0;
reg last_rd=0;
wire rd,wr,rd_valid,up_pop,ready,ack,reset_fifo,push,pop,empty;
wire [20:0] ra,wa;wire [31:0] wd,data,head;wire [8:0] count;wire [3:0] error;
wire busy=rd || wr || |pending;
assign rd_valid=pending[9];
assign pop=!empty;
wire [31:0] source_data=package_words[uploaded]^(bad_up && uploaded==128 ? 32'd1 : 32'd0);
wire test_response=dut.owner==5;
wire [5:0] fault_index=EARLY_READ ? response[8][5:0] : dut.responses[5:0];
wire [31:0] return_data=!test_response || fault==0 ? (EARLY_READ ? response[8] : response[9]) :
 fault==1 ? 32'd0 : fault==2 ? 32'hffffffff :
 fault==3 ? dut.test_pattern(fault_index-6'd1) :
 fault==4 ? dut.test_pattern(fault_index+6'd1) :
 (EARLY_READ ? response[8] : response[9])^32'h80000000;
wire [31:0] captured_data;
delta_read_capture capture(clk,rst,return_data,captured_data);
wire [31:0] aligned_data=CAPTURE_READ ? captured_data : return_data;
delta_memory #(.VERIFY_CACHE(1)) dut(clk,rst,1'b1,1'b0,busy,
 rd,ra,rd_valid,aligned_data,wr,wa,wd,uploaded==512,21'd512,uploaded==512,
 uploaded==512 ? 9'd0 : 9'd256,source_data,up_pop,ready,
 1'b0,1'b0,1'b0,,, ,9'd0,start,off,len,ack,reset_fifo,push,data,count,
 1'b0,21'd0,32'd0,,error,,crc,,,);
wfifo_32_32_512 fifo(.rst(rst|reset_fifo),.clkw(clk),.clkr(clk),.we(push),.di(data),.re(pop),.dout(head),
 .empty_flag(empty),.full_flag(),.rdusedw(count),.wrusedw(),.valid(),.afull(),.aempty());
always @(posedge clk)begin
 if(rst)begin uploaded<=0;pending<=0;corrupted<=0;last_rd<=0;counter<=0;end
 else begin
  pending<={pending[8:0],rd};if(rd)response[0]<=ram[ra];
  for(i=1;i<10;i=i+1)response[i]<=response[i-1];
  if(wr)ram[wa]<=wd;
  if(up_pop)uploaded<=uploaded+1;
  if(uploaded==512 && bad && !corrupted)begin ram[230528]<=ram[230528]^32'h1;corrupted<=1;end
  if(rd)begin
   if(!last_rd)begin if(ra[5:0]!=0)$fatal(1,"unaligned physical command/cache read");counter<=1;bursts=bursts+1;end
   else counter<=counter+1;
  end else if(last_rd && counter!=64)$fatal(1,"short native read: %d words",counter);
  last_rd<=rd;
  if(pop)begin
   if(head!==package_words[wanted+accepted])$fatal(1,"index/payload mismatch word=%d got=%h expected=%h",wanted+accepted,head,package_words[wanted+accepted]);
   accepted=accepted+1;
  end
 end
end
task read_stream;input integer offset,words;
 begin
  @(negedge clk);accepted=0;wanted=offset;off=offset;len=words;start=1;
  wait(ack);@(negedge clk);start=0;
  wait(accepted==words);repeat(30)@(negedge clk);
  if(accepted!=words || error)$fatal(1,"stream length/error mismatch");
 end
endtask
task restart;input integer injected;input input_fault;input ram_fault;
 begin
  @(negedge clk);rst=1;start=0;fault=injected;bad_up=input_fault;bad=ram_fault;
  repeat(5)@(negedge clk);rst=0;wait(ready || error);
 end
endtask
task expect_fault;input integer injected;input [3:0] wanted_error;
 begin
  restart(injected,0,0);
  if(ready || error!=wanted_error || dut.verify_started)$fatal(1,"BIST fault=%d got=%h want=%h",injected,error,wanted_error);
  if(dut.first_actual===dut.first_expected)$fatal(1,"first mismatch not captured");
 end
endtask
reg [1023:0] path;
initial begin
 if(!$value$plusargs("package=%s",path) || !$value$plusargs("crc=%h",crc))$fatal;
 $readmemh(path,package_words);repeat(5)@(negedge clk);rst=0;
 wait(ready || error);
 if(EXPECT_EARLY_FAIL)begin
  if(ready || error!=13)$fatal(1,"early-data model did not reproduce E2D: %h",error);
  $display("PASS read alignment reproduction: one-cycle early SDRAM data reproduces physical E2D with original direct connection");$finish;
 end
 if(error)$fatal(1,"good SDRAM cache rejected crc=%h wanted=%h",dut.verify_crc^32'hffffffff,crc);
 if(dut.verify_received!=512)$fatal(1,"cache marked ready before complete readback");
 for(j=0;j<20;j=j+1)read_stream(128+j*8,8);
 read_stream(384,1);read_stream(250,70);read_stream(511,1);
 $display("PASS cache: full SDRAM CRC readback, native FIFO, aligned 64-word physical reads, 8-word descriptors/prefixes, 1-word tail and boundary-crossing logical streams");
 restart(0,0,1);
 if(ready || error!=9)$fatal(1,"corrupted cache accepted");
 $display("PASS cache: post-upload corruption rejected as memory error 9 (E29)");
 restart(0,1,0);
 if(ready || error!=10 || dut.test_started || dut.verify_started)$fatal(1,"bad upload stream not rejected before BIST");
 expect_fault(1,14);expect_fault(2,15);expect_fault(3,12);expect_fault(4,13);expect_fault(5,11);
 $display("PASS cache diagnostics: upload corruption E2A; known-pattern zeros E2E, ones E2F, one-word late E2C, early E2D, other mismatch E2B; first bad word captured; no playback on errors");$finish;
end
initial begin #3000000;$fatal(1,"cache test timeout");end
endmodule
