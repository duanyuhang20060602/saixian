// Same 10:1 TMDS serialization as the vendor wrapper. Pixel-domain and
// serial-domain flops have separate, locally synchronized reset releases.
// A serial-clock reset must not directly release the pixel toggle flop.
module water_hdmi_phy(input I_pixel_clk,I_serial_clk,I_pixel_rst,I_serial_rst,
 input[9:0] I_tmds_channel_0,I_tmds_channel_1,I_tmds_channel_2,I_tmds_channel_clk,
 output O_tmds_ch0_p,O_tmds_ch1_p,O_tmds_ch2_p,O_tmds_clk_p);
reg toggle;
always @(posedge I_pixel_clk or posedge I_pixel_rst)
 if(I_pixel_rst)toggle<=0;else toggle<=~toggle;
reg[1:0] sync;reg[2:0] load;
always @(posedge I_serial_clk or posedge I_serial_rst)begin
 if(I_serial_rst)begin sync<=0;load<=0;end
 else begin sync<={sync[0],toggle};load<={load[1:0],sync[0]^sync[1]};end
end
wire[9:0] channels[0:3];wire[3:0] lanes;
assign channels[0]=I_tmds_channel_0;assign channels[1]=I_tmds_channel_1;
assign channels[2]=I_tmds_channel_2;assign channels[3]=I_tmds_channel_clk;
assign {O_tmds_clk_p,O_tmds_ch2_p,O_tmds_ch1_p,O_tmds_ch0_p}=lanes;
genvar lane,bit_index;
generate for(lane=0;lane<4;lane=lane+1)begin:g
 wire[9:0] reversed;
 for(bit_index=0;bit_index<10;bit_index=bit_index+1)begin:bits
  assign reversed[9-bit_index]=channels[lane][bit_index];
 end
 reg[9:0] shift;reg[1:0] pair;
 always @(posedge I_serial_clk or posedge I_serial_rst)begin
  if(I_serial_rst)begin shift<=0;pair<=0;end
  else begin
   if(load[2])shift<=reversed;else shift<=shift<<2;
   pair<=shift[9:8];
  end
 end
 EG_LOGIC_ODDR out_ddr(.clk(I_serial_clk),.rst(I_serial_rst),.d0(pair[1]),.d1(pair[0]),.q(lanes[lane]));
end endgenerate
endmodule
