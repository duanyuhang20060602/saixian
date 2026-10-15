// Native-size BMPs bypass interpolation RAM. Fail if this simulation ever
// enters that RAM path; this is deliberately not a vendor BRAM behavior model.
module EG_LOGIC_BRAM #(
 parameter DATA_WIDTH_A=24,ADDR_WIDTH_A=10,DATA_DEPTH_A=1024,
 DATA_WIDTH_B=24,ADDR_WIDTH_B=10,DATA_DEPTH_B=1024,
 BYTE_ENABLE=0,MODE="DP",REGMODE_A="NOREG",REGMODE_B="NOREG",
 WRITEMODE_A="NORMAL",WRITEMODE_B="NORMAL",RESETMODE="SYNC",
 DEBUGGABLE="NO",PACKABLE="NO",FORCE_KEEP="OFF",INIT_FILE="NONE",FILL_ALL="NONE",IMPLEMENT="32K"
)(output [DATA_WIDTH_A-1:0] doa,output [DATA_WIDTH_B-1:0] dob,
 input [DATA_WIDTH_A-1:0] dia,input [DATA_WIDTH_B-1:0] dib,
 input cea,ocea,clka,wea,rsta,ceb,oceb,clkb,web,rstb,bea,beb,
 input [ADDR_WIDTH_A-1:0] addra,input [ADDR_WIDTH_B-1:0] addrb);
assign doa={DATA_WIDTH_A{1'bx}};assign dob={DATA_WIDTH_B{1'bx}};
always @(posedge clka)if(cea)$fatal(1,"native-size asset unexpectedly wrote interpolation BRAM");
always @(posedge clkb)if(ceb)$fatal(1,"native-size asset unexpectedly read interpolation BRAM");
endmodule
