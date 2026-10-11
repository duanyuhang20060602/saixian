`timescale 1ns/1ps
module tb_decoder;
reg clk=0;always #10 clk=~clk;
reg rst=1,start=0,target=0;reg [20:0] encoded_words=0;
wire pop,patch_valid,done,error,busy;wire [20:0] addr;wire [31:0] value;
reg [31:0] package_words[0:809599];reg [31:0] image[0:921599],expected[0:460799];
reg [1023:0] path;string folder,expected_path;
integer ptr=0,cycle=0,i,j,pass,writes=0;
reg negative=0;reg [31:0] bad_word=0;
wire [3:0] error_kind;wire [95:0] fault_data;wire [31:0] encoded_crc;
wire stream_valid=(cycle%7)!=0;
wire patch_ready=(cycle%5)!=0;
delta_decoder #(.FRAME_WORDS(460800)) dut(clk,rst,start,target,encoded_words,negative ? bad_word : package_words[ptr],stream_valid,pop,
 patch_valid,addr,value,patch_ready,done,error,busy,error_kind,fault_data,encoded_crc,1'b1);
always @(posedge clk)begin
 cycle<=cycle+1;
 if(pop)ptr<=ptr+1;
 if(patch_valid && patch_ready)begin image[addr]<=value;writes=writes+1;end
end
task run;
 input integer index;input integer slot;
 begin
  @(negedge clk);ptr=package_words[128+index*8];encoded_words=package_words[129+index*8];target=slot;start=1;
  @(negedge clk);start=0;
  wait(done || error);@(negedge clk);
  if(error)$fatal(1,"decoder rejected valid descriptor %d",index);
  if(encoded_crc!==package_words[132+index*8])$fatal(1,"decoder input CRC mismatch descriptor %d",index);
  expected_path=$sformatf("%s/frame%0d.hex",folder,index);$readmemh(expected_path,expected);
  for(j=0;j<460800;j=j+1)if(image[slot*460800+j]!==expected[j])$fatal(1,"descriptor %d slot %d word %d got=%h expected=%h",index,slot,j,image[slot*460800+j],expected[j]);
 end
endtask
initial begin
 if(!$value$plusargs("package=%s",path) || !$value$plusargs("folder=%s",folder))$fatal;
 $readmemh(path,package_words);for(j=0;j<921600;j=j+1)image[j]=0;
 repeat(4)@(negedge clk);rst=0;
 for(i=0;i<2;i=i+1)begin run(i,i%2);run(i,1-i%2);end
 $display("PASS decoder: 720p tagged plate, no-op loop delta, both mirrored buffers; writes=%d",writes);
 negative=1;
 for(i=0;i<6;i=i+1)begin
  @(negedge clk);rst=1;repeat(3)@(negedge clk);rst=0;
  case(i)0:bad_word=0;1:bad_word=32'hc0000001;2:bad_word=460801;3:bad_word=32'h40000002;
   4:bad_word=32'h80000001;5:bad_word=1;endcase
  encoded_words=1;start=1;@(negedge clk);start=0;wait(error);@(negedge clk);
  if(error_kind!==i+1 || fault_data[31:0]!==bad_word)$fatal(1,"decoder diagnostic wrong case %d code %d",i,error_kind);
  if(i==5 && (fault_data[95:64]!=1 || fault_data[63:32]!=1))$fatal(1,"final cursor diagnostic missing");
 end
 $display("PASS decoder: six error kinds, offending command, word position and final cursor; encoded input CRC for every frame and loop-back");$finish;
end
initial begin #500000000;$fatal(1,"timeout");end
endmodule
