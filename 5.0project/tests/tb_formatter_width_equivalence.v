`timescale 1ns/1ps
module tb;
reg clk=0,rst=1,ready=0,refresh=0;
always #5 clk=~clk;
reg[2:0]page=1;reg[15:0]rng=16'h19a7;
wire av,bv,ac,bc;wire[7:0]ad,bd;
saixian_hmi_status_tx #(.CLK_FREQ_HZ(100000000),.ENHANCEMENT_FEEDBACK(1),.BYTE_STREAM(1)) a(
 .clk(clk),.rst(rst),.image_count(3'd6),.audio_count(3'd5),.error_code(3'd7),.initializing(1'b0),.page_id(page),.refresh_request(refresh),
 .sharpness(2'd3),.brightness(4'd8),.contrast(4'd8),.saturation(4'd8),.volume(4'd8),.invert(1'b1),.vintage(1'b1),.enhancement(2'd2),
 .event_state(4'd6),.minutes(7'd99),.seconds(6'd59),.command_sent_pulse(ac),.byte_valid(av),.byte_data(ad),.byte_ready(ready));
saixian_hmi_status_tx_width_reference #(.CLK_FREQ_HZ(100000000),.ENHANCEMENT_FEEDBACK(1),.BYTE_STREAM(1)) b(
 .clk(clk),.rst(rst),.image_count(3'd6),.audio_count(3'd5),.error_code(3'd7),.initializing(1'b0),.page_id(page),.refresh_request(refresh),
 .sharpness(2'd3),.brightness(4'd8),.contrast(4'd8),.saturation(4'd8),.volume(4'd8),.invert(1'b1),.vintage(1'b1),.enhancement(2'd2),
 .event_state(4'd6),.minutes(7'd99),.seconds(6'd59),.command_sent_pulse(bc),.byte_valid(bv),.byte_data(bd),.byte_ready(ready));
integer i,bytes=0,commands=0;
always @(posedge clk)if(!rst)begin
 if(av!==bv || ac!==bc || a.refresh_count!==b.refresh_count || a.tx_state!==b.tx_state || a.prefix_length!==b.prefix_length || a.suffix_length!==b.suffix_length)$fatal(1,"cycle mismatch");
 if(av && ready)begin if(ad!==bd)$fatal(1,"byte mismatch");bytes=bytes+1;end
 if(ac)commands=commands+1;
end
initial begin
 repeat(5)@(negedge clk);rst=0;
 for(i=0;i<30000;i=i+1)begin
  rng={rng[14:0],rng[15]^rng[13]^rng[12]^rng[10]};ready=rng[0];refresh=i%3000==0;
  if(i%6000==0)begin page=(i/6000+1)%5;a.refresh_count=24999998;b.refresh_count=24999998;end
  @(negedge clk);
 end
 if(bytes<400 || commands<14)$fatal(1,"insufficient coverage");
 $display("PASS 100MHz formatter cycle equivalence: %0d bytes, %0d commands, refresh wrap, five pages, maximum settings and random backpressure",bytes,commands);$finish;
end
endmodule
