`timescale 1ns/1ps
module tb;
reg sd=0,px=0;always #10 sd=~sd;always #6.6665 px=~px;
reg rst=1,enable=0,play=0;wire req,we,re,valid,empty,full;wire[31:0] sector,word,data;wire[10:0] used;
reg[7:0] byte_data=0;reg byte_valid=0,sector_end=0;
wire[23:0] left_pcm,right_pcm,sink_left,sink_right;wire sink_valid,acr_valid;wire[19:0] cts,acr_n;
reg[26:0] phase=0;wire tick=phase>=75000000-48000;
wire[31:0] underruns;
water_audio_output output_stage(.clk(px),.rst(rst),.sample_tick(tick),.cycle_mode(1'b0),.source_left(left_pcm),.source_right(right_pcm),
 .pcm_valid(sink_valid),.pcm_left(sink_left),.pcm_right(sink_right));
audio_arc_calculate acr(.I_clk(px),.I_rst(rst),.I_audio_valid(sink_valid),.O_acr_valid(acr_valid),.O_acr_cts(cts),.O_acr_n(acr_n));
saixian_sd_audio_stream #(.FIFO_BITS(11),.REFILL_LEVEL(1536)) stream(.clk(sd),.rst(rst),.enable(enable),.start_sector(32'd123),.data_bytes(32'd2052),
 .fifo_wrusedw(used),.sd_sec_read(req),.sd_sec_read_addr(sector),.sd_sec_read_data(byte_data),
 .sd_sec_read_data_valid(byte_valid),.sd_sec_read_end(sector_end),.pcm_we(we),.pcm_word(word));
rfifo_32_32_512 #(.ADDR_WIDTH_W(11),.ADDR_WIDTH_R(11),.AL_FULL_NUM(2045)) fifo(.rst(rst),.clkw(sd),.clkr(px),.we(we),.di(word),.re(re),.dout(data),.valid(valid),.empty_flag(empty),.full_flag(full),.wrusedw(used));
always @(posedge px)if(rst)phase<=0;else phase<=tick ? phase-(75000000-48000):phase+48000;
saixian_pcm_player player(.clk(px),.rst(rst),.play_enable(play),.sample_tick(tick),.fifo_empty(empty),.fifo_data(data),.fifo_valid(valid),.fifo_read(re),.audio_left(left_pcm),.audio_right(right_pcm),.underrun_count(underruns));
function[31:0] pattern;input integer n;begin pattern={16'(n*4117+77),16'(n*7919-12000)};end endfunction
integer n,j,idx,played=0,written=0,sunk=0,acr_seen=0;reg stalled=0;reg[31:0] p;
always @(posedge sd)if(!rst&&we)begin
 if(full)$fatal(1,"audio overflow");
 if(word!==pattern(written%513))$fatal(1,"SD byte assembly %0d got%h",written,word);
 written=written+1;
end
always @(posedge px)if(!rst&&play&&tick)begin
 #1;p=pattern(played%513);
 if(left_pcm!=={p[15:0],8'd0}||right_pcm!=={p[31:16],8'd0})$fatal(1,"PCM sample %0d mismatch L%h R%h expected%h ready%b",played,left_pcm,right_pcm,p,player.sample_ready);
 played=played+1;

end
always @(posedge px)if(!rst)begin
 if(acr_valid)begin
  if(acr_n!=6144||(acr_seen>0&&cts!=75000))$fatal(1,"HDMI ACR N/CTS mismatch %0d/%0d",acr_n,cts);
  acr_seen=acr_seen+1;
 end
 if(play&&sink_valid)begin
  p=pattern(sunk%513);
  if(sink_left!=={p[15:0],8'd0}||sink_right!=={p[31:16],8'd0})$fatal(1,"HDMI input PCM alignment sample%0d",sunk);
  sunk=sunk+1;
  if(sunk==1200)begin
   if(underruns!=0||acr_seen<24||!stalled)$fatal(1,"audio underrun/ACR/stall coverage");
   $display("PASS audio chain: 1200 exact stereo samples to HDMI input, actual 2048-sample async FIFO, 16ms card delay, partial-sector loop, N6144/CTS75000, zero underruns");$finish;
  end
 end
end
initial begin
 repeat(12)@(negedge sd);rst=0;enable=1;
 fork
  begin wait(used>=1500);repeat(50)@(negedge px);play=1;end
  forever begin
   wait(req);if(played>200&&!stalled)begin stalled=1;repeat(800000)@(negedge sd);end
   repeat(15)@(negedge sd);
   for(j=0;j<512;j=j+1)begin
    idx=(sector-123)*512+j;p=pattern(idx/4);
    byte_data=p>>((idx%4)*8);byte_valid=1;@(negedge sd);byte_valid=0;
    repeat(31)@(negedge sd);
   end
   sector_end=1;@(negedge sd);sector_end=0;wait(!req);repeat(100)@(negedge sd);
  end
 join
end
initial begin #50000000;$fatal(1,"audio timeout samples%0d",played);end
endmodule

