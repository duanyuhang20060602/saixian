`timescale 1ns/1ps
module tb;
reg clk=0,rst=1,enable=0,frame_tick=0,begin_packet=0,word_valid=0,finish_packet=0,commit_packet=0,request_sent=0;
always #5 clk=~clk;
reg [8:0] word_index;reg [31:0] word_data,sent_descriptor;wire[31:0] request_descriptor;wire active_valid,rejected;wire[4:0] display_angle;reg[4:0]desired_angle=3;
photo_relief_tables_compact_a dut(.clk(clk),.rst(rst),.enable(enable),.frame_tick(frame_tick),.desired_angle(desired_angle),.desired_light_x(6'sd4),.desired_light_y(6'sd5),.request_descriptor(request_descriptor),.request_sent(request_sent),.sent_descriptor(sent_descriptor),.begin_packet(begin_packet),.word_valid(word_valid),.finish_packet(finish_packet),.commit_packet(commit_packet),.word_index(word_index),.word_data(word_data),.active_valid(active_valid),.display_angle(display_angle),.mem_clk(clk),.mem_rst(rst),.mem_enable(enable),.rejected(rejected));
integer i,job;reg[31:0]descriptor;
initial begin
 repeat(5)@(negedge clk);rst=0;enable=1;repeat(5)@(negedge clk);
 for(job=0;job<3;job=job+1)begin
 desired_angle=3+job;repeat(2)@(negedge clk);descriptor=request_descriptor;sent_descriptor=descriptor;request_sent=1;@(negedge clk);request_sent=0;
 begin_packet=1;@(negedge clk);begin_packet=0;
 for(i=0;i<385;i=i+1)begin
 word_index=i;word_data=i==0 ? descriptor:32'h12340000+i;word_valid=1;
 // Compact SPI commits with the final real word, without a CRC slot.
 if(i==384)begin finish_packet=1;commit_packet=1;end
 @(negedge clk);word_valid=0;finish_packet=0;commit_packet=0;repeat(15)@(negedge clk);
 end
 frame_tick=1;@(negedge clk);frame_tick=0;repeat(3)@(negedge clk);
 if(!active_valid || rejected || display_angle!=3+job)$fatal(1,"trophy table not published angle=%d valid=%b rejected=%b",display_angle,active_valid,rejected);
 end
 $display("PASS compact trophy tables publish three rotating angles with last-word commit and no CRC slot");$finish;
end
endmodule
