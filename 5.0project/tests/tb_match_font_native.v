`timescale 1ns/1ps
module tb;
reg clk=0;always #5 clk=~clk;
reg[8:0] text_address=511;reg direct=1;reg[6:0] direct_glyph=0;reg[3:0] row=0;wire[15:0] bits;
photo_match_font d(clk,text_address,direct,direct_glyph,row,bits);
reg[15:0] original[0:2047];reg[7:0] chars[0:511];integer g,r,a,count=0;
task check;input integer id,rr,aa,dd;
begin
 @(negedge clk);direct=dd;direct_glyph=id;text_address=aa;row=rr;
 @(posedge clk);@(posedge clk);#1;
 if(bits!==original[id*16+rr])$fatal(1,"native packed font glyph=%d row=%d string=%d direct=%d got=%h expected=%h",id,rr,aa,dd,bits,original[id*16+rr]);
 count=count+1;
end endtask
initial begin
 $readmemh("original_font.hex",original);$readmemh("text_ids.hex",chars);
 for(g=0;g<107;g=g+1)for(r=0;r<16;r=r+1)check(g,r,511,1);
 for(a=0;a<512;a=a+1)for(r=0;r<16;r=r+1)check(chars[a],r,a,0);
 $display("PASS native dual-port font: %d bitmap/string/row checks using independent MIF conversion",count);$finish;
end
endmodule
