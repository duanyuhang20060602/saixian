// 64 stream words and four row descriptors share two RAM9K blocks.
// The decoder predicts its next byte read, retaining one decoded byte/clock.
module photo_relief_decode_cache(input clk,we,input [6:0] wa,input [31:0] wd,
 input [6:0] ra,output [31:0] rd);
`ifdef RELIEF_SIM
 reg [31:0] memory[0:127];reg [31:0] q;
 always @(posedge clk)begin if(we)memory[wa]<=wd;q<=memory[ra];end
 assign rd=q;
`else
 EG_LOGIC_BRAM #(.DATA_WIDTH_A(32),.ADDR_WIDTH_A(7),.DATA_DEPTH_A(128),
  .DATA_WIDTH_B(32),.ADDR_WIDTH_B(7),.DATA_DEPTH_B(128),.BYTE_ENABLE(0),
  .MODE("PDPW"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),
  .WRITEMODE_A("NORMAL"),.WRITEMODE_B("NORMAL"),.RESETMODE("SYNC"),.IMPLEMENT("9K")) memory(
  .clka(clk),.rsta(1'b0),.cea(1'b1),.wea(we),.ocea(1'b1),.bea(1'b0),.addra(wa),.dia(wd),.doa(),
  .clkb(clk),.rstb(1'b0),.ceb(1'b1),.web(1'b0),.oceb(1'b1),.beb(1'b0),.addrb(ra),.dib(32'd0),.dob(rd));
`endif
endmodule

// Preserve the old seven/twelve-cycle RGB taps. Small distributed memories
// replace three under-filled true-dual-port RAM9K blocks.
module photo_award_delay_lut(input clk,rst,input [23:0] rgb_in,output [23:0] rgb,menu_rgb);
reg [2:0] first;reg [1:0] second;reg [3:0] age;
wire [23:0] a,b;reg [23:0] qa,qb;
always @(posedge clk)begin
 if(rst)begin first<=0;second<=0;age<=0;end
 else begin first<=first==5 ? 3'd0:first+1'b1;second<=second+1'b1;if(age<12)age<=age+1'b1;end
 qa<=a;qb<=b;
end
`ifdef RELIEF_SIM
reg [23:0] ma[0:7],mb[0:3];
always @(posedge clk)if(!rst)begin ma[first]<=rgb_in;mb[second]<=menu_rgb;end
assign a=ma[first];assign b=mb[second];
`else
EG_LOGIC_DRAM #(.DATA_WIDTH_W(24),.DATA_WIDTH_R(24),.ADDR_WIDTH_W(3),.ADDR_WIDTH_R(3),
 .DATA_DEPTH_W(8),.DATA_DEPTH_R(8)) first_ram(.di(rgb_in),.waddr(first),.we(!rst),.wclk(clk),.raddr(first),.do(a));
EG_LOGIC_DRAM #(.DATA_WIDTH_W(24),.DATA_WIDTH_R(24),.ADDR_WIDTH_W(2),.ADDR_WIDTH_R(2),
 .DATA_DEPTH_W(4),.DATA_DEPTH_R(4)) second_ram(.di(menu_rgb),.waddr(second),.we(!rst),.wclk(clk),.raddr(second),.do(b));
`endif
assign menu_rgb=age>=7 ? qa:24'd0;
assign rgb=age>=12 ? qb:24'd0;
endmodule
