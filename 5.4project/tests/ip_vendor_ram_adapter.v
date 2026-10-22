// Port/parameter adapter to Anlogic's unmodified plaintext ram_infer model.
// This tests the eRAM contract; implementation and packing come from TD.
module EG_LOGIC_BRAM #(
 parameter integer DATA_WIDTH_A=24,ADDR_WIDTH_A=4,DATA_DEPTH_A=16,
 DATA_WIDTH_B=24,ADDR_WIDTH_B=4,DATA_DEPTH_B=16,BYTE_ENABLE=0,
 parameter
 MODE="DP",REGMODE_A="NOREG",REGMODE_B="NOREG",WRITEMODE_A="NORMAL",
 WRITEMODE_B="NORMAL",RESETMODE="SYNC",IMPLEMENT="9K",INIT_FILE="NONE",
 DEBUGGABLE="NO",PACKABLE="NO",FORCE_KEEP="OFF",FILL_ALL="NONE")(
 input clka,rsta,cea,wea,ocea,bea,input [ADDR_WIDTH_A-1:0] addra,
 input [DATA_WIDTH_A-1:0] dia,output [DATA_WIDTH_A-1:0] doa,
 input clkb,rstb,ceb,web,oceb,beb,input [ADDR_WIDTH_B-1:0] addrb,
 input [DATA_WIDTH_B-1:0] dib,output [DATA_WIDTH_B-1:0] dob);
 `include "ip_init_map.vh"
 ram_infer #(.MODE(MODE=="PDPW" ? "SDP":MODE),.USE_BYTE_WEA(0),.USE_BYTE_WEB(0),
 .DATAWIDTH_A(DATA_WIDTH_A),.ADDRWIDTH_A(ADDR_WIDTH_A),.DATADEPTH_A(DATA_DEPTH_A),
 .DATAWIDTH_B(DATA_WIDTH_B),.ADDRWIDTH_B(ADDR_WIDTH_B),.DATADEPTH_B(DATA_DEPTH_B),
 .REGMODE_A(REGMODE_A),.REGMODE_B(REGMODE_B),.RESETMODE_A(RESETMODE),.RESETMODE_B(RESETMODE),
 .INIT_FILE(HEX_FILE),.WRITEMODE_A(WRITEMODE_A),.WRITEMODE_B(WRITEMODE_B)) model(
 .clka(clka),.rsta(rsta),.cea(cea),.ocea(ocea),.wea(wea),.dia(dia),.addra(addra),.doa(doa),
 .clkb(clkb),.rstb(rstb),.ceb(ceb),.oceb(oceb),.web(web),.dib(dib),.addrb(addrb),.dob(dob));
 // This supplier model declares INIT_FILE but never loads it. Load the
 // independently converted IP MIF after its time-zero fill, before any clock.
 // Read/write, clock-enable and collision behavior remain the supplier model.
 initial begin
   #1;
   if (HEX_FILE!="") $readmemh(HEX_FILE,model.memory);
 end
endmodule
