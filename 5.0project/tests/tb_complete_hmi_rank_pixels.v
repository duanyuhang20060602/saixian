`timescale 1ns/1ps
module tb;
reg clk=0,rst=1,head=0,rb=0,rf=0,wv=0;always #5 clk=~clk;
reg[9:0] ha=0;reg[2:0] row=0,ri=0;reg[8:0] x=0,wi=0;reg[3:0] fy=0,len=8;reg[15:0] tm=16'h1234;reg[31:0] wd=0;wire[31:0] bits;
saixian_sprint_runtime d(.clk(clk),.rst(rst),.header(head),.header_addr(ha),.row_id(row),.x(x),.font_y(fy),.bits(bits),.rank_begin(rb),.rank_finish(rf),.rank_failed(1'b0),.rank_index(ri),.rank_length(len),.rank_time(tm),.word_valid(wv),.word_index(wi),.word_data(wd));
reg[15:0] initial_font[0:2047],initial_header[0:2047],gold[0:1023];integer r,c,y,p,k,idx,col,cell_index,off;reg pixel;reg[15:0] f;reg[31:0] wanted;integer cases=0;
function[3:0] lane;input integer n;begin case(n)0:lane=4;1:lane=5;2:lane=3;3:lane=6;4:lane=2;5:lane=7;6:lane=1;default:lane=8;endcase end endfunction
function[15:0] timecode;input integer n;begin case(n)0:timecode=16'h1023;1:timecode=16'h1031;2:timecode=16'h1038;3:timecode=16'h1046;4:timecode=16'h1055;5:timecode=16'h1063;6:timecode=16'h1076;default:timecode=16'h1091;endcase end endfunction
reg[15:0] mark;
task pixels;input custom;begin
 for(r=0;r<8;r=r+1)for(y=1;y<=14;y=y+1)for(p=0;p<512;p=p+1)begin
  row=r;fy=y;x=p;repeat(3)@(negedge clk);idx=-1;col=0;
  cell_index=p/32;col=(p%32)/2;mark=custom ? 16'h1234:timecode(r);
  case(cell_index)
   0:idx=r+1;1:idx=lane(r);2:idx=11;
   3,4,5,6,7,8,9,10:begin
    if(custom)idx=-(2+r*128+(cell_index-3)*16+y);
    else case(cell_index)3:idx=13;4:idx=14;5:idx=0;6:idx=r+1;default:idx=-1;endcase
   end
   11:idx=mark[15:12];12:idx=mark[11:8];13:idx=10;14:idx=mark[7:4];15:idx=mark[3:0];
  endcase
  pixel=0;if(idx>=0)begin f=initial_font[1024+idx*16+y];pixel=f[15-col];end
  else if(idx< -1)begin f=gold[-idx-2];pixel=f[15-col];end
  wanted={32{pixel}};
  if(bits!==wanted)$fatal(1,"rank pixel differs custom=%0d row=%0d x=%0d y=%0d got=%h expected=%h",custom,r,p,y,bits,wanted);
  cases=cases+1;
 end
end endtask
initial begin
 $readmemh("photo_rank_header.hex",initial_header);$readmemh("photo_rank_glyphs.hex",initial_font);
 repeat(4)@(negedge clk);rst=0;head=1;
 for(p=0;p<1024;p=p+1)begin ha=p;repeat(3)@(negedge clk);if(bits!=={initial_header[p*2+1],initial_header[p*2]})$fatal(1,"original header differs %0d",p);end
 head=0;pixels(0);
 for(r=0;r<8;r=r+1)begin
  ri=r;rb=1;@(negedge clk);rb=0;
  for(c=0;c<64;c=c+1)begin
   wi=r*64+c;wd=32'h5a39c6e7^(wi*32'h1234567);gold[wi*2]=wd[31:16];gold[wi*2+1]=wd[15:0];wv=1;
   @(negedge clk);wv=0;repeat(2)@(negedge clk);
  end
  rf=1;@(negedge clk);rf=0;
 end
 pixels(1);
 rst=1;repeat(3)@(negedge clk);rst=0;pixels(0);
 $display("PASS runtime ranking: all1024 original heading words, %0d default/edited/reset pixels, all eight 8-glyph banks, independent lanes and SS.CC times, default restoration after RAM edits",cases);$finish;
end
initial begin #20000000;$fatal(1,"rank pixel timeout");end
endmodule
