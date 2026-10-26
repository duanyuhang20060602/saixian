`timescale 1ns/1ps
module event_trophy_rom(input clk,input [2:0] angle,input [6:0] x,y,output [3:0] index);
// Four 4-bit pixels per word. Each row is 24 words, each angle 2304.
// Explicit shifts keep the address calculation out of the DSP column.
wire [14:0] frame_base={1'b0,angle,11'd0}+{4'd0,angle,8'd0};
wire [14:0] row_base={4'd0,y,4'd0}+{5'd0,y,3'd0};
wire [14:0] wa=frame_base+row_base+{10'd0,x[6:2]};wire [15:0] q[0:8];
reg [3:0] bank;reg [1:0] nibble;
always @(posedge clk)begin bank<=wa[14:11];nibble<=x[1:0];end
genvar g;
generate for(g=0;g<9;g=g+1)begin:roms
 localparam FILE_HEX=g==0 ? "trophy_0.hex":g==1 ? "trophy_1.hex":g==2 ? "trophy_2.hex":g==3 ? "trophy_3.hex":g==4 ? "trophy_4.hex":g==5 ? "trophy_5.hex":g==6 ? "trophy_6.hex":g==7 ? "trophy_7.hex":"trophy_8.hex";
 localparam FILE_MIF=g==0 ? "trophy_0.mif":g==1 ? "trophy_1.mif":g==2 ? "trophy_2.mif":g==3 ? "trophy_3.mif":g==4 ? "trophy_4.mif":g==5 ? "trophy_5.mif":g==6 ? "trophy_6.mif":g==7 ? "trophy_7.mif":"trophy_8.mif";
`ifdef MATCH_SIM
 reg [15:0] data[0:2047];reg [15:0] value;initial $readmemh(FILE_HEX,data);
 always @(posedge clk)value<=data[wa[10:0]];
 assign q[g]=value;
`else
 EG_LOGIC_BRAM #(.DATA_WIDTH_A(16),.ADDR_WIDTH_A(11),.DATA_DEPTH_A(2048),
  .DATA_WIDTH_B(16),.ADDR_WIDTH_B(11),.DATA_DEPTH_B(2048),.BYTE_ENABLE(0),.MODE("SP"),
  .REGMODE_A("NOREG"),.REGMODE_B("NOREG"),.WRITEMODE_A("NORMAL"),.WRITEMODE_B("NORMAL"),
  .RESETMODE("SYNC"),.INIT_FILE(FILE_MIF),.FILL_ALL("NONE"),.IMPLEMENT("32K")) mem(
  .clka(clk),.rsta(1'b0),.cea(1'b1),.ocea(1'b1),.wea(1'b0),.dia(16'd0),.doa(q[g]),.addra(wa[10:0]),.bea(1'b0),
  .clkb(clk),.rstb(1'b0),.ceb(1'b0),.oceb(1'b0),.web(1'b0),.dib(16'd0),.dob(),.addrb(11'd0),.beb(1'b0));
`endif
end endgenerate
wire [15:0] selected=bank<9 ? q[bank]:16'd0;
assign index=(selected>>(nibble*4))&4'hf;
endmodule
