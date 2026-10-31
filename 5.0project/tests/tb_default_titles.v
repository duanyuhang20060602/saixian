`timescale 1ns/1ps
module tb;
reg clk=0;always #5 clk=~clk;reg rst=1,tick=0,we=0;reg [7:0] wi=0;reg [6:0] glyph=0;reg [3:0] row=0;
wire [15:0] bits;wire [4:0] title_length,ticker_length;reg [15:0] expected[0:175];integer bank,c,r,n=0;
saixian_font_rom #(.DEFAULT_TEXT(1),.SERIAL_TEXT(1),.TITLE_SD(1),.INDEPENDENT_TEXT(1)) dut(
 .clk(clk),.rst(rst),.frame_tick(tick),.word_valid(we),.word_index(wi),.word_data(32'h12345678),.word_length(5'd1),
 .title_length(title_length),.ticker_length(ticker_length),.glyph_id(glyph),.row(row),.bits(bits));
initial begin
 $readmemh("defaults_expected.hex",expected);
 repeat(5)@(negedge clk);rst=0;
 if(title_length!=4 || ticker_length!=7)$fatal(1,"defaults absent");
 for(bank=0;bank<2;bank=bank+1)for(c=0;c<(bank==0 ? 4:7);c=c+1)for(r=0;r<16;r=r+1)begin
  glyph=96+bank*16+c;row=r;repeat(2)@(negedge clk);
  if(bits!==expected[n])$fatal(1,"default glyph wrong bank=%0d char=%0d row=%0d",bank,c,r);n=n+1;
 end
 for(c=0;c<8;c=c+1)begin wi=c;we=1;@(negedge clk);we=0;repeat(2)@(negedge clk);end
 tick=1;@(negedge clk);tick=0;repeat(2)@(negedge clk);
 if(title_length!=1 || ticker_length!=7)$fatal(1,"UART overwrite did not preserve other default");
 $display("PASS 176 default font rows: 100m/title and welcome ticker initialize without new RAM, UART overwrite preserves ticker");$finish;
end
endmodule
