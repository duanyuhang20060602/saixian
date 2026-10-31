// Synchronous9-bit column map replaces repeated pixel-rate x comparisons.
module photo_match_columns(input clk,input[9:0] address,output[8:0] data);
`ifdef MATCH_SIM
reg[8:0] words[0:1023];reg[8:0] q;
initial $readmemh("photo_match_columns.hex",words);
always @(posedge clk)q<=words[address];assign data=q;
`else
EG_LOGIC_BRAM #(.DATA_WIDTH_A(9),.ADDR_WIDTH_A(10),.DATA_DEPTH_A(1024),
 .DATA_WIDTH_B(9),.ADDR_WIDTH_B(10),.DATA_DEPTH_B(1024),.MODE("DP"),
 .REGMODE_A("NOREG"),.REGMODE_B("NOREG"),.WRITEMODE_A("NORMAL"),.WRITEMODE_B("NORMAL"),
 .RESETMODE("SYNC"),.IMPLEMENT("9K"),.INIT_FILE("photo_match_columns.mif")) memory(
 .clka(clk),.cea(1'b1),.ocea(1'b1),.wea(1'b0),.rsta(1'b0),.dia(9'd0),.addra(address),.doa(data),.bea(1'b0),
 .clkb(clk),.ceb(1'b0),.oceb(1'b0),.web(1'b0),.rstb(1'b0),.dib(9'd0),.addrb(10'd0),.dob(),.beb(1'b0));
`endif
endmodule
