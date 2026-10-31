`timescale 1ns/1ps
module tb;
reg clk=0,mc=0;always #6.667 clk=~clk;always #10 mc=~mc;
reg rst=1,en=0,tick=0,sent=0,beginp=0,wv=0,finish=0,commit=0;
reg [4:0] angle=0;reg signed [5:0] lx=-16,ly=6;reg [31:0] sentd=0,wd=0;reg [8:0] wi=0;
wire [31:0] query;wire avail,active,bank,pwe,wwe,rejected;wire [4:0] display_angle;wire signed [5:0] display_x,display_y;
wire [8:0] pwa;wire [31:0] pwd;wire [7:0] wwa;wire [23:0] wwd;
reg [31:0] palette[0:511];reg [23:0] walls[0:255];reg [31:0] descriptor,old_descriptor;integer i,writes=0,wallwrites=0;
photo_relief_tables_compact_a dut(.clk(clk),.rst(rst),.enable(en),.frame_tick(tick),.desired_angle(angle),.desired_light_x(lx),.desired_light_y(ly),
 .request_descriptor(query),.request_sent(sent),.sent_descriptor(sentd),.available(avail),.begin_packet(beginp),.word_valid(wv),.finish_packet(finish),.commit_packet(commit),
 .word_index(wi),.word_data(wd),.active_valid(active),.active_bank(bank),.display_angle(display_angle),.display_light_x(display_x),.display_light_y(display_y),
 .wall_we(wwe),.wall_wa(wwa),.wall_wd(wwd),.mem_clk(mc),.mem_rst(rst),.mem_enable(en),.palette_we(pwe),.palette_wa(pwa),.palette_wd(pwd),.rejected(rejected));
always @(posedge mc)if(pwe)begin palette[pwa]<=pwd;writes=writes+1;end
always @(posedge clk)if(wwe)begin walls[wwa]<=wwd;wallwrites=wallwrites+1;end
task sendword;input [8:0] index;input [31:0] value;begin wi=index;wd=value;wv=1;@(negedge clk);wv=0;repeat(16)@(negedge clk);end endtask
task issue;begin sentd=query;sent=1;@(negedge clk);sent=0;descriptor=sentd;repeat(4)@(negedge clk);end endtask
task packet;input [31:0] desc;input good;input integer words;input shortgap;begin
 beginp=1;@(negedge clk);beginp=0;sendword(0,desc);
 for(i=1;i<=words;i=i+1)begin
  if(shortgap)begin wi=i;wd={i[23:0],7'b0,1'b1};wv=1;@(negedge clk);end
  else sendword(i,{i[23:0],7'b0,1'b1});
 end
 wv=0;repeat(20)@(negedge clk);finish=1;commit=good;@(negedge clk);finish=0;commit=0;repeat(4)@(negedge clk);
end endtask
task blank;begin tick=1;@(negedge clk);tick=0;repeat(3)@(negedge clk);end endtask
initial begin
 repeat(8)@(negedge clk);rst=0;en=1;repeat(8)@(negedge clk);issue;old_descriptor=descriptor;
 packet(descriptor,1,384,0);if(active)$fatal(1,"table visible before blank");if(avail)$fatal(1,"pending bank reusable");
 blank;if(!active || bank!=1 || display_angle!=0 || display_x!=-16 || display_y!=6)$fatal(1,"atomic commit failed");
 for(i=1;i<=256;i=i+1)if(palette[256+i-1]!=={i[23:0],7'b0,1'b1})$fatal(1,"CDC palette write %0d",i);
 for(i=257;i<=384;i=i+1)if(walls[128+i-257]!==i[23:0])$fatal(1,"wall write %0d",i);
 angle=23;lx=24;ly=-16;repeat(4)@(negedge clk);issue;
 packet(descriptor,0,384,0);blank;if(bank!=1 || display_angle!=0)$fatal(1,"bad CRC visible");
 packet(descriptor,1,383,0);blank;if(bank!=1)$fatal(1,"incomplete table visible");
 packet(descriptor,1,384,1);blank;if(bank!=1)$fatal(1,"mailbox overflow visible");
 packet(descriptor,1,384,0);blank;if(bank!=0 || display_angle!=23 || display_x!=24 || display_y!=-16)$fatal(1,"new descriptor not committed");
 en=0;repeat(10)@(negedge clk);en=1;repeat(10)@(negedge clk);issue;
 packet(old_descriptor,1,384,0);blank;if(active)$fatal(1,"stale owner visible after reentry");
 packet(descriptor,1,384,0);blank;if(!active)$fatal(1,"valid reentry not published");
 $display("PASS atomic table/angle/light commit, all dual-clock palette and wall words, CRC failure, short packet, mailbox overflow, scene owner replay rejection; writes=%0d wall=%0d",writes,wallwrites);$finish;
end
initial begin #2000000;$fatal(1,"receiver timeout");end
endmodule
