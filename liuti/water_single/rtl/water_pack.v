// One RGB565 pair per SDRAM word; the first source pixel occupies the MSB.
module water_pack(input clk,rst,write_req,pixel_valid,input[23:0] pixel,
 input full,output reg valid,output reg[31:0] data,output reg overflow,
 output reg small_valid,output reg[31:0] small_data);
reg half,small_half;reg[15:0] first,small_first,previous_odd;reg[9:0] pair_x;
wire[15:0] p={pixel[23:19],pixel[15:10],pixel[7:3]};
// Samples are centred on source x=0,2,4,..., matching reconstruction.
// The old pair average was centred at x=0.5,2.5,... and moved the picture
// when changing between the effect plane and native scanout.
wire[15:0] left=pair_x==0 ? first:previous_odd;
wire[6:0] r={left[15:11]}+{first[15:11],1'b0}+{p[15:11]}+7'd2;
wire[7:0] g={left[10:5]}+{first[10:5],1'b0}+{p[10:5]}+8'd2;
wire[6:0] b={left[4:0]}+{first[4:0],1'b0}+{p[4:0]}+7'd2;
wire[15:0] average={r[6:2],g[7:2],b[6:2]};
always @(posedge clk)begin
 if(rst)begin valid<=0;data<=0;half<=0;first<=0;overflow<=0;small_half<=0;small_first<=0;small_valid<=0;small_data<=0;previous_odd<=0;pair_x<=0;end
 else begin
  valid<=0;small_valid<=0;
  if(write_req)begin half<=0;small_half<=0;pair_x<=0;previous_odd<=0;end
  else if(pixel_valid)begin
   if(!half)begin first<=p;half<=1;end
   else begin
    data<={first,p};valid<=1;half<=0;
    previous_odd<=p;pair_x<=pair_x==639 ? 0:pair_x+1'b1;
    if(!small_half)begin small_first<=average;small_half<=1;end
    else begin small_data<={small_first,average};small_valid<=1;small_half<=0;end
   end
  end
  if(valid&&full)overflow<=1;
 end
end
endmodule
