`timescale 1ns/1ps
module tb;
reg clk=0,rst=1,bv=0,ready=0,timeout=0,rv=0,err=0;reg[7:0] b=0,rtag=0,pos=0;
always #5 clk=~clk;
wire req,busy;wire[7:0] tag,bank,ci;wire[13:0] code;
photo_serial_text_runtime_a #(.BOOT_TEXT(1),.RANK_INPUT(1)) d(.clk(clk),.rst(rst),.byte_valid(bv),.byte_data(b),.can_start(1'b1),.timeout(timeout),.boot_ready(ready),.reply_valid(rv),.reply_tag(rtag),.reply_position(pos),.reply_error(err),.active(busy),.request_valid(req),.tag(tag),.bank_length(bank),.character_index(ci),.code(code));
task send;input[7:0] x;begin @(negedge clk);b=x;bv=1;@(negedge clk);bv=0;end endtask
task ack;begin @(negedge clk);rv=1;rtag=tag;pos={ci[3:0],3'd7,1'b0};@(negedge clk);rv=0;if(d.loading && !req)wait(req);end endtask
function[13:0] wanted;input integer i;begin case(i)0:wanted=49;1:wanted=48;2:wanted=48;3:wanted=3378;4:wanted=2593;5:wanted=4840;6:wanted=3061;7:wanted=2036;8:wanted=4964;9:wanted=2116;10:wanted=2636;default:wanted=0;endcase end endfunction
integer i,j,gb_high,gb_low;
task startup;begin
 ready=0;repeat(5)@(negedge clk);if(req)$fatal(1,"default text started before complete scan");ready=1;
 for(j=0;j<2;j=j+1)begin
  wait(req);@(negedge clk);
  if(bank!==(j==0 ? 8'd4:8'h87))$fatal(1,"wrong default bank/length %h",bank);
  for(i=0;i<(j==0 ? 4:7);i=i+1)begin
   if(ci!=i || code!=wanted(i+(j==0 ? 0:4)))$fatal(1,"wrong startup character %0d/%0d %0d",j,i,code);
   ack;
  end
  wait(!req);@(negedge clk);
 end
 repeat(3)@(negedge clk);if(req)$fatal(1,"defaults repeated forever");
end endtask
task rank_start;input[7:0] rank;begin send("@");send("R");send(rank);send(":");end endtask
task mark;begin send(",");send("0");send("9");send(".");send("8");send("7");send(13);send(10);end endtask
initial begin
 repeat(4)@(negedge clk);rst=0;startup;
 rank_start("1");send(8'hb0);send(8'ha1);send("X");mark;wait(req);
 if(!req || !tag[7] || d.rank_index!=0 || d.rank_length!=2 || d.rank_time!=16'h0987 || bank!=2 || code!=1538)$fatal(1,"valid Chinese rank metadata failed");
 ack;if(code!=88)$fatal(1,"ASCII rank name code");ack;if(!d.rank_finish)$fatal(1,"rank completion missing");@(negedge clk);
 rank_start("8");for(i=0;i<8;i=i+1)send("Z");mark;wait(req);
 if(!req || bank!=8'he8 || d.rank_index!=7 || d.rank_length!=8)$fatal(1,"eighth rank or eight-character boundary");
 for(i=0;i<8;i=i+1)ack;@(negedge clk);
 rank_start("1");for(i=0;i<9;i=i+1)send("Z");mark;if(req)$fatal(1,"long name silently accepted");
 rank_start("2");send("X");send(",");send("9");send(".");send("8");send("7");send(13);send(10);if(req)$fatal(1,"short seconds accepted");
 rank_start("2");send("X");send(",");send("0");send("9");send(".");send("8");send("7");send(13);send("X");if(req)$fatal(1,"missing CRLF accepted");
 rank_start("9");send("X");mark;if(req)$fatal(1,"invalid rank accepted");
 rank_start("1");send("X");timeout=1;@(negedge clk);timeout=0;if(busy)$fatal(1,"timeout did not abort");
 send("@");send("0");send(":");send("Y");send(13);wait(req);if(!req || tag[7] || code!=89)$fatal(1,"caption compatibility");ack;@(negedge clk);
 for(gb_high=161;gb_high<=254;gb_high=gb_high+1)for(gb_low=161;gb_low<=254;gb_low=gb_low+1)begin
  send("@");send("0");send(":");send(gb_high);send(gb_low);send(13);wait(req);
  if(tag[7] || bank!=1 || ci!=0 || code!=128+(gb_high-161)*94+gb_low-161)
   $fatal(1,"GB2312 glyph index changed: %h %h -> %0d",gb_high,gb_low,code);
  ack;@(negedge clk);
 end
 rst=1;repeat(3)@(negedge clk);rst=0;startup;
 $display("PASS cold/soft-reset SD default reload, all8836 GB2312 glyph indices, ASCII ranks, all eight banks, eight-character limit, exact SS.CC/CRLF, overflow/timeout recovery, caption compatibility");$finish;
end
initial begin #3000000;$fatal(1,"parser timeout");end
endmodule
