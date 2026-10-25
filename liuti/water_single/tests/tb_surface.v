`timescale 1ns/1ps
module tb;
reg clk=0;always #5 clk=~clk;
reg rst=1,valid=0;reg[31:0] rgb;reg[4:0] shade;reg[2:0] shine;
wire ov;wire[31:0] got,ref_word;
water_surface_light d(clk,rst,valid,rgb,shade,shine,ov,got);
water_effect_light reference(rgb,shade,shine,ref_word);
reg[31:0] expected[0:65535];integer head=0,tail=0,i,j,seed=1888;
always @(posedge clk)begin #1;
 if(ov)begin
  if(head>=tail||got!==expected[head])$fatal(1,"surface mismatch %0d got%h expected%h",head,got,expected[head]);
  head=head+1;
 end
end
initial begin
 repeat(4)@(negedge clk);rst=0;
 for(i=0;i<32768;i=i+1)begin
  @(negedge clk);valid=1;rgb={$random(seed)};shade=(i>>6)&31;shine=(i>>11)&7;
  // Sweep all 64 green values, every shade/highlight setting, random R/B.
  rgb[10:5]=i&63;rgb[26:21]=63-(i&63);
  #1;expected[tail]=ref_word;tail=tail+1;
  @(negedge clk);valid=0;rgb=$random(seed);shade=$random(seed);shine=$random(seed);
  if(i%19==0)repeat(i%4)@(negedge clk);
 end
 repeat(8)@(negedge clk);if(head!=tail)$fatal(1,"surface result missing");
 // Reset flushes an accepted half-pair; it must never escape into a new frame.
 valid=1;@(negedge clk);valid=0;rst=1;repeat(4)@(negedge clk);rst=0;
 repeat(6)@(negedge clk);if(ov)$fatal(1,"surface reset leaked pending pixel");
 $display("PASS folded surface lighting: %0d exact packed RGB565 pairs, all shades/highlights and green values, gaps and reset flush",head);$finish;
end
initial begin #2000000;$fatal(1,"surface timeout");end
endmodule
