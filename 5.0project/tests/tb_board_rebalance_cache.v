`timescale 1ns/1ps
module tb;
reg clk=0,rst=1,remote=0,bp=0,wv=0,finish=0,commit=0,tick=0,we=0;
always #6.667 clk=~clk;
reg [8:0] wi=0;reg [31:0] wd=0;reg [4:0] band=0;reg [7:0] index=0,wa=0,ra=0;reg [23:0] rwd=0;
wire [23:0] rgb;wire [6:0] height,peak;wire [31:0] wave;wire fft,wave_valid;
reg [23:0] wall[0:127];reg [31:0] tables[0:18431];integer i,j;
photo_av_metadata_a #(.EDGE_METADATA(1),.REMOTE_RELIEF(1)) dut(.clk(clk),.rst(rst),.frame_tick(tick),.play_position(32'd1024),
 .begin_packet(bp),.word_valid(wv),.finish_packet(finish),.commit_packet(commit),.word_index(wi),.word_data(wd),
 .read_band(band),.read_index(index),.height(height),.peak(peak),.extrema(wave),.fft_valid(fft),.wave_valid(wave_valid),
 .remote_enable(remote),.remote_we(we),.remote_wa(wa),.remote_wd(rwd),.remote_ra(ra),.remote_rd(rgb));
task packet;begin
 bp=1;@(negedge clk);bp=0;
 for(j=0;j<290;j=j+1)begin wi=j;wd=j==0 ? 32'h41320003:j==1 ? 32'd0:j<34 ? {18'd0,7'd100,7'd60}:32'h7f802040;wv=1;@(negedge clk);end
 wv=0;finish=1;commit=1;@(negedge clk);finish=0;commit=0;repeat(10)@(negedge clk);tick=1;@(negedge clk);tick=0;repeat(4)@(negedge clk);
 if(!fft || !wave_valid || height!=60 || peak!=100 || wave!=32'h7f802040)$fatal(1,"AV changed across shared cache %0d %0d %0d %h",fft,height,peak,wave);
end endtask
initial begin
 $readmemh("wall_table.hex",wall);$readmemh("tables_expected.hex",tables);
 repeat(8)@(negedge clk);rst=0;packet;
 rst=1;remote=1;@(negedge clk);rst=0;
 for(i=0;i<256;i=i+1)begin we=1;wa=i;rwd=tables[256+i%128][31:8];@(negedge clk);end we=0;
 for(i=0;i<256;i=i+1)begin ra=i;repeat(2)@(negedge clk);if(rgb!==wall[i%128])$fatal(1,"lossless 17-bit wall decode %0d %h/%h",i,rgb,wall[i%128]);end
 rst=1;remote=0;@(negedge clk);rst=0;packet;
 $display("PASS shared 18-bit FFT/wall RAM, every lossless wall color in both banks, exact audio metadata before and after scene ownership change");$finish;
end
endmodule

// Functional synchronous dual-port RAM contract used by existing Anlogic IP.
module EG_LOGIC_BRAM #(parameter DATA_WIDTH_A=32,ADDR_WIDTH_A=10,DATA_DEPTH_A=1024,
 DATA_WIDTH_B=32,ADDR_WIDTH_B=10,DATA_DEPTH_B=1024,BYTE_ENABLE=0,MODE="PDPW",
 REGMODE_A="NOREG",REGMODE_B="NOREG",WRITEMODE_A="NORMAL",WRITEMODE_B="NORMAL",RESETMODE="SYNC",IMPLEMENT="9K")(
 input clka,rsta,cea,wea,ocea,bea,input [ADDR_WIDTH_A-1:0] addra,input [DATA_WIDTH_A-1:0] dia,output reg [DATA_WIDTH_A-1:0] doa,
 input clkb,rstb,ceb,web,oceb,beb,input [ADDR_WIDTH_B-1:0] addrb,input [DATA_WIDTH_B-1:0] dib,output reg [DATA_WIDTH_B-1:0] dob);
 reg [DATA_WIDTH_A-1:0] memory[0:DATA_DEPTH_A-1];
 always @(posedge clka)if(cea)begin if(wea)memory[addra]<=dia;doa<=memory[addra];end
 always @(posedge clkb)if(ceb)begin if(web)memory[addrb]<=dib;dob<=memory[addrb];end
endmodule
