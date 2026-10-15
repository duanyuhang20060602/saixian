// B owns image enhancement. A only preserves the established 15-clock
// neutral processing latency; no second enhancement/adjustment engine.
module photo_neutral_delay(
 input clk,rst,de,input [23:0] rgb_in,output [23:0] rgb_out
);
reg [23:0] pixels[0:14];reg [5:0] valid;integer i;
always @(posedge clk or posedge rst)begin
 if(rst)begin valid<=0;for(i=0;i<15;i=i+1)pixels[i]<=0;end
 else begin
  valid<={valid[4:0],de};pixels[0]<=rgb_in;
  for(i=1;i<15;i=i+1)if(i==6)pixels[i]<=valid[5] ? pixels[i-1]:24'd0;else pixels[i]<=pixels[i-1];
 end
end
assign rgb_out=pixels[14];
endmodule

// Four colour clocks, matching the original style/fade/range pipeline.
// Gain is frame-stable in blanking. At the midpoint level 63 is true black.
module photo_display_fade(
 input clk,rst,input [5:0] darkness,input [23:0] rgb_in,output reg [23:0] rgb_out
);
reg [23:0] source,dimmed;reg [6:0] gain;
reg [15:0] red_range,green_range,blue_range;
function [7:0] fade;
 input [7:0] value;input [6:0] amount;reg [14:0] product;
 begin product=value*amount;fade=product[13:6];end
endfunction
always @(posedge clk or posedge rst)begin
 if(rst)begin source<=0;dimmed<=0;gain<=64;red_range<=0;green_range<=0;blue_range<=0;rgb_out<=24'h101010;end
 else begin
  source<=rgb_in;gain<=darkness==63 ? 7'd0:7'd64-{1'b0,darkness};
  dimmed<={fade(source[23:16],gain),fade(source[15:8],gain),fade(source[7:0],gain)};
  red_range<=dimmed[23:16]*8'd219+16'd128;
  green_range<=dimmed[15:8]*8'd219+16'd128;
  blue_range<=dimmed[7:0]*8'd219+16'd128;
  rgb_out<={8'd16+red_range[15:8],8'd16+green_range[15:8],8'd16+blue_range[15:8]};
 end
end
endmodule
