`timescale 1ns/1ps
module tb;
reg clk=0,rst=1,drain=0,read_en=0;integer era=0,tick=0,seed=32'h63cb164e;
wire req,pcm_we,empty,full,old_empty,old_full;wire[31:0] sector,pcm,data,old_data;wire[13:0] used,old_used;
reg byte_valid=0,block_end=0;reg[7:0] byte_data=0;
reg[1:0] sdstate=0;integer position=0,source_byte=0,delay=0,sector_number=0;
integer written=0,checked=0,total_checked=0,max_used=0;reg pending=0;
always #5 clk=~clk;
function[31:0] sample;input integer n,e;begin sample=((n+17)*32'd16777619)^32'h5a39c17e^(e*32'h8ac17d29);end endfunction
photo_sd_audio_stream stream(.clk(clk),.rst(rst),.enable(1'b1),.start_sector(32'd20),.data_bytes(32'd32768),
 .fifo_wrusedw(used),.sd_sec_read(req),.sd_sec_read_addr(sector),.sd_sec_read_data(byte_data),
 .sd_sec_read_data_valid(byte_valid),.sd_sec_read_end(block_end),.pcm_we(pcm_we),.pcm_word(pcm));
photo_audio_fifo_compact dut(.clk(clk),.rst(rst),.write_en(pcm_we),.write_data(pcm),.read_en(read_en),.data(data),.empty(empty),.full(full),.used(used));
photo_audio_fifo #(.RAM32_HEAD(4096)) baseline(.clk(clk),.rst(rst),.write_en(pcm_we),.write_data(pcm),.read_en(read_en),.data(old_data),.empty(old_empty),.full(old_full),.used(old_used));
always @(posedge clk)begin
 if(rst)begin pending<=0;written=0;end
 else begin
  pending<=read_en && !empty;
  if(pcm_we)begin
   if(pcm!==sample(written,era))$fatal(1,"sector PCM mismatch %0d",written);
   written=written+1;
  end
 end
end
always @(negedge clk)begin
 if(rst)begin
  checked=0;tick=0;read_en=0;byte_valid=0;block_end=0;sdstate=0;position=0;source_byte=0;delay=0;sector_number=0;
 end else begin
  if(used!==old_used || empty!==old_empty || full || old_full)$fatal(1,"occupancy/capacity mismatch %0d/%0d",used,old_used);
  if(used>4225)$fatal(1,"refill occupancy bound exceeded %0d",used);
  if(used>max_used)max_used=used;
  if(pending)begin
   if(data!==old_data || data!==sample(checked,era))$fatal(1,"compact PCM order/latency mismatch frame %0d got %h old %h",checked,data,old_data);
   checked=checked+1;total_checked=total_checked+1;
  end
  tick=tick+1;seed=(seed<<1)^(seed<0 ? 32'h04c11db7:0);
  read_en=drain && !empty && tick%5!=0 && seed[3:0]<7;
  byte_valid=0;block_end=0;
  case(sdstate)
   0:if(req)begin sdstate=1;position=0;delay=(sector_number%4==0) ? 97:seed[6:0];sector_number=sector_number+1;end
   1:if(delay!=0)delay=delay-1;else if(seed[1:0]!=0)begin
    byte_data=sample(source_byte/4,era)>>(8*(source_byte%4));byte_valid=1;source_byte=source_byte+1;
    if(position==511)begin
     if(sector_number%2==0)begin block_end=1;sdstate=3;end
     else begin delay=3;sdstate=2;end
    end else position=position+1;
   end
   2:if(delay!=0)delay=delay-1;else begin block_end=1;sdstate=3;end
   3:if(!req)sdstate=0;
  endcase
 end
end
initial begin
 repeat(5)@(negedge clk);rst=0;
 wait(used>=4224);repeat(200)@(negedge clk);drain=1;wait(checked>=18000);
 wait(sdstate==1 && position>50 && position<200);@(posedge clk);#1;rst=1;era=1;drain=0;
 repeat(5)@(negedge clk);rst=0;wait(used>=4224);repeat(200)@(negedge clk);drain=1;wait(checked>=12000);
 if(max_used<4224 || total_checked<30000)$fatal(1,"coverage");
 $display("PASS %0d cycle-exact raw PCM frames vs 8192 baseline; max occupancy %0d <=4225; 4352 pointer/head-tail wraps, concurrent reads/writes, refill pauses, last-byte/end overlap and in-flight reset",total_checked,max_used);$finish;
end
initial begin #200000000;$fatal(1,"compact FIFO timeout");end
endmodule
