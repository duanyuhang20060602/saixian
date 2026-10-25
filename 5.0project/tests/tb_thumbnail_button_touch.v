`timescale 1ns/1ps
module tb_thumbnail_touch;
reg clk=0;always #5 clk=~clk;
reg rst=1,rx=1,boot=1,result=0,carousel=1;integer next_count=0;
always @(posedge clk)if(dut.photo_next_event)next_count=next_count+1;
top_photo_a dut(.clk(clk),.key(4'hf),.hmi_uart_rx(rx));
defparam dut.screen_rx.CLK_FREQ_HZ=1152000;
defparam dut.pointer.CLK_HZ=1152000;
initial begin
 force dut.pixel_clk=clk;force dut.rst_pixel=rst;
 force dut.blank_start=1'b1;force dut.presses=4'd0;
 force dut.boot_active=boot;force dut.result_busy=result;force dut.carousel_mode=carousel;
end
task tx;input [7:0] b;integer i;
begin @(negedge clk);rx=0;repeat(10)@(negedge clk);
 for(i=0;i<8;i=i+1)begin rx=b[i];repeat(10)@(negedge clk);end
 rx=1;repeat(10)@(negedge clk);end endtask
task touch;input [15:0] x,y;input down;
reg [7:0] sum;
begin sum=8'ha6+x[7:0]+x[15:8]+y[7:0]+y[15:8]+down;
 tx('ha6);tx(x[7:0]);tx(x[15:8]);tx(y[7:0]);tx(y[15:8]);tx(down);
 tx(sum);tx(255);tx(255);tx(255);repeat(20)@(negedge clk);end endtask
task tap;begin touch(100,100,1);repeat(34560)@(negedge clk);touch(100,100,0);end endtask
task cmd;input [7:0] v;
begin tx('h55);tx('h31);tx(v);tx(0);tx(255);tx(255);tx(255);repeat(20)@(negedge clk);end endtask
initial begin
 repeat(5)@(negedge clk);rst=0;repeat(10)@(negedge clk);
 if(dut.pointer_enabled!==0)$fatal(1,"boot must block pointer");
 boot=0;repeat(10)@(negedge clk);if(!dut.pointer_enabled)$fatal(1,"MOUSE default enabled");
 touch(100,200,1);touch(380,40,1);touch(380,40,0);
 if(dut.cursor_x!=1200 || dut.cursor_y!=40 || dut.settings_mode)$fatal(1,"drag to launcher");
 tap();if(!dut.settings_mode)$fatal(1,"UART tap must open actual top menu");
 touch(400,100,1);touch(100,160,1);touch(100,160,0);
 if(dut.cursor_x!=600 || dut.cursor_y!=160)$fatal(1,"drag to volume");
 tap();if(dut.volume!=6 || dut.setting_item!=0)$fatal(1,"UART tap must increase actual volume");
 // Move to left half of the same row.
 touch(200,100,1);touch(50,100,1);touch(50,100,0);
 tap();if(dut.volume!=5)$fatal(1,"left half must decrease");
 // Adjust the added interval row through the real MOUSE UART path.
 touch(100,100,1);touch(250,308,1);touch(250,308,0);
 if(dut.cursor_x!=600 || dut.cursor_y!=576)$fatal(1,"drag to interval row");
 tap();if(dut.auto_interval_seconds!=6 || dut.setting_item!=13)$fatal(1,"touch interval increase");
 touch(200,100,1);touch(50,100,1);touch(50,100,0);
 tap();if(dut.auto_interval_seconds!=5)$fatal(1,"touch interval decrease");
 touch(100,308,1);touch(100,100,1);touch(100,100,0);
 cmd(0);if(dut.pointer_enabled)$fatal(1,"disable command");
 tap();if(dut.volume!=5)$fatal(1,"disabled touch must not edit");
 cmd(1);result=1;repeat(5)@(negedge clk);tap();if(dut.volume!=5 || dut.pointer_enabled)$fatal(1,"result context must block");
 result=0;carousel=0;repeat(5)@(negedge clk);if(dut.pointer_enabled)$fatal(1,"event context must block");
 // Exercise the registered edge-control path with unrelated scene blocks omitted.
 force dut.edge_enable=1'b1;force dut.display_valid=1'b1;
 force dut.award_active=1'b0;force dut.award_loading=1'b0;force dut.settings_mode=1'b0;
 carousel=1;force dut.count=3'd2;repeat(3)@(negedge clk);
 // Existing cursor is (300,160): drag to next arrow, then short UART tap.
 touch(100,100,1);touch(560,200,1);touch(560,200,0);
 if(dut.cursor_x!=1220 || dut.cursor_y!=360)$fatal(1,"drag to next arrow");
 force dut.thumbnail_visible=1'b0;tap();repeat(3)@(negedge clk);
 if(next_count!=0)$fatal(1,"removed arrow retained a hidden hot spot");
 force dut.thumbnail_visible=1'b1;tap();repeat(3)@(negedge clk);
 if(next_count!=1)$fatal(1,"visible preview must replace next arrow");
 // The live preview uses exactly the existing queued next-photo event.
 force dut.thumbnail_visible=1'b1;
 touch(100,100,1);touch(70,100,1);touch(70,100,0);
 if(dut.cursor_x!=1160 || dut.cursor_y!=360)$fatal(1,"drag to thumbnail");
 tap();repeat(3)@(negedge clk);if(next_count!=2)$fatal(1,"thumbnail tap must pulse once");
 force dut.thumbnail_visible=1'b0;tap();if(next_count!=2)$fatal(1,"hidden thumbnail accepted a tap");
 force dut.thumbnail_visible=1'b1;
 touch(100,100,1);touch(100,205,1);touch(100,205,0);
 if(dut.cursor_y!=570)$fatal(1,"drag to obsolete preview position");
 tap();if(next_count!=2)$fatal(1,"old thumbnail position retained a hot spot");
 touch(100,230,1);touch(130,125,1);touch(130,125,0);
 force dut.settings_mode=1'b1;tap();if(next_count!=2)$fatal(1,"menu blocks next arrow");
 force dut.settings_mode=1'b0;force dut.award_active=1'b1;tap();if(next_count!=2)$fatal(1,"award blocks next arrow");
 force dut.award_active=1'b0;force dut.count=3'd1;tap();if(next_count!=2)$fatal(1,"single photo hides next arrow");
 force dut.count=3'd2;repeat(3)@(negedge clk);
 if(dut.music_drive_q!==1)$fatal(1,"edge control must enable after staging");
 result=1;repeat(3)@(negedge clk);
 if(dut.music_drive_q!==0)$fatal(1,"result must clear staged edge control");
 result=0;boot=1;repeat(3)@(negedge clk);
 if(dut.music_drive_q!==0)$fatal(1,"boot must block staged edge control");
 $display("PASS moved preview replaces arrow; hidden/old-position taps rejected; actual top wiring: UART -> gesture -> launcher -> menu volume, drag rejection, default enable, mode and boot/result/event gates (other hardware blocks omitted)");$finish;
end
initial begin #100000000;$fatal(1,"top test timeout");end
endmodule
