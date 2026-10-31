`timescale 1ns/1ps
module tb;
reg clk=0,rst=1,enable=0,bv=0,ended=0;
always #5 clk=~clk;
reg[31:0] base=100,bytes=0;reg[13:0] used=4096;reg[7:0] byte_data=0;
wire req,old_req,we,old_we;wire[31:0] address,old_address,word_data,old_word;
integer cycles=0,words=0,cases=0,n,j,k,blocks,spacing,overlap;
photo_sd_audio_stream dut(clk,rst,enable,base,bytes,used,req,address,byte_data,bv,ended,we,word_data);
reference_audio_stream golden(clk,rst,enable,base,bytes,used,old_req,old_address,byte_data,bv,ended,old_we,old_word);
always @(negedge clk)if(!rst)begin
 cycles=cycles+1;
 if({req,address,we,word_data}!=={old_req,old_address,old_we,old_word})
  $fatal(1,"audio file output changed cycle=%d length=%d",cycles,bytes);
 if(we)words=words+1;
end
task run;
 input integer length,gap,same_end;
 begin
  @(negedge clk);rst=1;enable=0;bv=0;ended=0;bytes=length;base=100+cases*100;used=4100;
  repeat(4)@(negedge clk);rst=0;enable=1;
  repeat(5)@(negedge clk);if(req)$fatal(1,"refill ignored waterline");used=4096;
  if(length==0)begin repeat(12)@(negedge clk);if(req || we)$fatal(1,"empty audio requested data");end
  else begin
   blocks=(length+511)/512;
   // Two complete loops include the last partial sector and first sector
   // after wrapping back to the file start. The PHY always returns 512 bytes.
   for(k=0;k<blocks*2;k=k+1)begin
    wait(req);if(address!=base+k%blocks)$fatal(1,"wrong audio sector address");
    repeat(2)@(negedge clk);
    for(j=0;j<512;j=j+1)begin
     bv=1;byte_data=(j*71+k*13+cases)&255;ended=same_end && j==511;
     @(negedge clk);bv=0;ended=0;repeat(gap)@(negedge clk);
    end
    if(!same_end)begin ended=1;@(negedge clk);ended=0;end
    // Pause new requests so the zero-gap completion cannot be mistaken
    // for an already outstanding request in the next loop iteration.
    used=4100;repeat(3)@(negedge clk);used=4096;
   end
  end
  @(negedge clk);enable=0;repeat(4)@(negedge clk);cases=cases+1;
 end
endtask
initial begin
 for(spacing=0;spacing<3;spacing=spacing+1)for(overlap=0;overlap<2;overlap=overlap+1)begin
  run(0,spacing,overlap);run(1,spacing,overlap);run(3,spacing,overlap);run(4,spacing,overlap);
  run(511,spacing,overlap);run(512,spacing,overlap);run(513,spacing,overlap);run(1023,spacing,overlap);run(2049,spacing,overlap);
 end
 $display("PASS audio sector windows: %d cases, %d PCM words, every output cycle identical to exact f6",cases,words);$finish;
end
initial begin #10000000;$fatal(1,"audio window timeout");end
endmodule
