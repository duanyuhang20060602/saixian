// The same single physical 32K RAM has read A and write B ports.
module EG_LOGIC_BRAM #(
parameter DATA_WIDTH_A=16,ADDR_WIDTH_A=11,DATA_DEPTH_A=2048,
 DATA_WIDTH_B=16,ADDR_WIDTH_B=11,DATA_DEPTH_B=2048,BYTE_ENABLE=0,
 MODE="DP",REGMODE_A="NOREG",REGMODE_B="NOREG",WRITEMODE_A="NORMAL",WRITEMODE_B="NORMAL",
 RESETMODE="SYNC",DEBUGGABLE="NO",PACKABLE="NO",FORCE_KEEP="OFF",INIT_FILE="",FILL_ALL="NONE",IMPLEMENT="32K")(
 input clka,rsta,cea,wea,ocea,bea,input [ADDR_WIDTH_A-1:0] addra,input [DATA_WIDTH_A-1:0] dia,
 output reg [DATA_WIDTH_A-1:0] doa,
 input clkb,rstb,ceb,web,oceb,beb,input [ADDR_WIDTH_B-1:0] addrb,input [DATA_WIDTH_B-1:0] dib,
 output reg [DATA_WIDTH_B-1:0] dob);
reg [DATA_WIDTH_A-1:0] memory[0:2047];integer i;
initial begin
 for(i=0;i<2048;i=i+1)memory[i]=16'ha55a;
 if(INIT_FILE=="rank_names.mif")$readmemh("common/rank_names.hex",memory);
 if(INIT_FILE=="rank_digits.mif")$readmemh("common/rank_digits.hex",memory,0,511);
end
always @(posedge clka)if(cea)begin if(wea)memory[addra]<=dia;doa<=memory[addra];end
always @(posedge clkb)if(ceb)begin if(web)memory[addrb]<=dib;dob<=memory[addrb];end
endmodule
