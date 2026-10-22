// Functional synchronous BRAM model for testing production primitive wiring.
// This is not a device timing model; TD routed timing is checked separately.
module EG_LOGIC_BRAM #(
 parameter DATA_WIDTH_A=16,ADDR_WIDTH_A=9,DATA_DEPTH_A=512,
 DATA_WIDTH_B=16,ADDR_WIDTH_B=9,DATA_DEPTH_B=512,
 BYTE_ENABLE=0,MODE="PDPW",REGMODE_A="NOREG",REGMODE_B="NOREG",
 WRITEMODE_A="NORMAL",WRITEMODE_B="NORMAL",RESETMODE="SYNC",
 DEBUGGABLE="NO",PACKABLE="NO",FORCE_KEEP="OFF",INIT_FILE="NONE",FILL_ALL="NONE",IMPLEMENT="9K"
)(
 output reg [DATA_WIDTH_A-1:0] doa,output reg [DATA_WIDTH_B-1:0] dob,
 input [DATA_WIDTH_A-1:0] dia,input [DATA_WIDTH_B-1:0] dib,
 input cea,ocea,clka,wea,rsta,ceb,oceb,clkb,web,rstb,bea,beb,
 input [ADDR_WIDTH_A-1:0] addra,input [ADDR_WIDTH_B-1:0] addrb
);
reg [DATA_WIDTH_A-1:0] mem[0:DATA_DEPTH_A-1];
initial begin
 if(INIT_FILE=="saixian_av_hann_half.hex_0_0.mif")$readmemh("common/audio_ui/saixian_av_hann_half.hex",mem);
 else if(INIT_FILE=="saixian_av_twiddle_serial.hex_0_0.mif")$readmemh("common/audio_ui/saixian_av_twiddle_serial.hex",mem);
 else if(INIT_FILE!="NONE")$fatal(1,"unexpected primitive initialization file");
end
always @(posedge clka)if(cea)begin doa<=mem[addra];if(wea)mem[addra]<=dia;end
always @(posedge clkb)if(ceb)begin dob<=mem[addrb];if(web)mem[addrb]<=dib;end
endmodule
