// Exact original mapping: 16 + floor((219*x + 128)/256).
// Complement identity: 16 + x - floor((37*x + 127)/256).
// Only the six-bit correction is retained; 37*x = (x<<5)+(x<<2)+x.
// Two clocks, preserving the original board video latency.
module fluid_rgb_limited(input clk,input[23:0]rgb,output reg[23:0]limited_rgb);
wire[7:0]r=rgb[23:16],g=rgb[15:8],b=rgb[7:0];
wire[13:0]r37={1'b0,r,5'b0}+{4'b0,r,2'b0}+{6'b0,r}+14'd127;
wire[13:0]g37={1'b0,g,5'b0}+{4'b0,g,2'b0}+{6'b0,g}+14'd127;
wire[13:0]b37={1'b0,b,5'b0}+{4'b0,b,2'b0}+{6'b0,b}+14'd127;
reg[5:0]cr,cg,cb;reg[23:0]original;
wire[7:0]lr=8'd16+original[23:16]-{2'b0,cr};
wire[7:0]lg=8'd16+original[15:8]-{2'b0,cg};
wire[7:0]lb=8'd16+original[7:0]-{2'b0,cb};
always @(posedge clk)begin
 original<=rgb;cr<=r37[13:8];cg<=g37[13:8];cb<=b37[13:8];
 limited_rgb<={lr,lg,lb};
end
endmodule
