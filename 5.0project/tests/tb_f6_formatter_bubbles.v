`timescale 1ns/1ps
module tb;
parameter STALL=0,LEVEL=8;
reg clk=0,rst=1,ready=1;always #5 clk=~clk;
reg[2:0] page=1;reg[15:0]rng=16'hf6a5;
wire av,bv,ac,bc;wire[7:0]ad,bd;reg[7:0] abuf[0:1023],bbuf[0:1023];
integer na=0,nb=0,ca=0,cb=0,ticks=0,ta=0,tb_=0,i,p,goal;
saixian_hmi_status_tx #(.CLK_FREQ_HZ(100000000),.ENHANCEMENT_FEEDBACK(1),.BYTE_STREAM(1)) a(
 .clk(clk),.rst(rst),.image_count(3'd6),.audio_count(3'd5),.error_code(3'd7),.initializing(1'b0),.page_id(page),.refresh_request(1'b0),
 .sharpness(LEVEL[1:0]),.brightness(LEVEL[3:0]),.contrast(LEVEL[3:0]),.saturation(LEVEL[3:0]),.volume(LEVEL[3:0]),.invert(LEVEL[0]),.vintage(LEVEL[1]),.enhancement(LEVEL[1:0]),
 .event_state(LEVEL[3:0]),.minutes(7'd99),.seconds(6'd59),.command_sent_pulse(ac),.byte_valid(av),.byte_data(ad),.byte_ready(ready));
saixian_hmi_status_tx_f6_before #(.CLK_FREQ_HZ(100000000),.ENHANCEMENT_FEEDBACK(1),.BYTE_STREAM(1)) b(
 .clk(clk),.rst(rst),.image_count(3'd6),.audio_count(3'd5),.error_code(3'd7),.initializing(1'b0),.page_id(page),.refresh_request(1'b0),
 .sharpness(LEVEL[1:0]),.brightness(LEVEL[3:0]),.contrast(LEVEL[3:0]),.saturation(LEVEL[3:0]),.volume(LEVEL[3:0]),.invert(LEVEL[0]),.vintage(LEVEL[1]),.enhancement(LEVEL[1:0]),
 .event_state(LEVEL[3:0]),.minutes(7'd99),.seconds(6'd59),.command_sent_pulse(bc),.byte_valid(bv),.byte_data(bd),.byte_ready(ready));
always @(negedge clk)begin rng={rng[14:0],rng[15]^rng[13]^rng[12]^rng[10]};ready=!STALL || rng[0] && rng[3];end
always @(posedge clk)if(!rst)begin
 ticks=ticks+1;
 if(ca<goal && av && ready)begin abuf[na]=ad;na=na+1;end
 if(cb<goal && bv && ready)begin bbuf[nb]=bd;nb=nb+1;end
 if(ac && ca<goal)begin ca=ca+1;if(ca==goal)ta=ticks;end
 if(bc && cb<goal)begin cb=cb+1;if(cb==goal)tb_=ticks;end
 if(a.refresh_count!==b.refresh_count)$fatal(1,"refresh cycle changed");
end
initial begin
 for(p=0;p<3;p=p+1)begin
  rst=1;page=p;goal=p==1 ? 14:3;na=0;nb=0;ca=0;cb=0;ticks=0;ta=0;tb_=0;
  repeat(5)@(negedge clk);rst=0;
  // Exercise the exact periodic timer rollover without waiting 25M clocks.
  a.refresh_count=24999998;b.refresh_count=24999998;
  wait(ca==goal && cb==goal);@(negedge clk);
  if(na!=nb)$fatal(1,"byte count changed %d %d",na,nb);
  for(i=0;i<na;i=i+1)if(abuf[i]!==bbuf[i])$fatal(1,"byte mismatch page=%d index=%d",p,i);
  if(!STALL && ta>=tb_)$fatal(1,"no bubble reduction");
  $display("PASS page=%0d stall=%0d bytes=%0d clocks_before=%0d clocks_after=%0d",p,STALL,na,tb_,ta);
 end
 $display("PASS formatter bubble removal preserves bytes, maximum 32-byte command, periodic timing and boundaries");$finish;
end
initial begin #10000000;$fatal(1,"timeout");end
endmodule
