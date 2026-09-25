`timescale 1ns/1ps
module tb_blue_victory;
reg clk=0; always #5 clk=~clk;
reg rst=1,frame_tick=0,trigger=0,de=0,vs=0;
reg select_blue=0,select_red=0,select_sprint=0;
reg [10:0] x=0; reg [9:0] y=0;
reg [23:0] rgb=24'h123456;
wire busy,deo,vso; wire [23:0] out;
saixian_battle_result_fx dut(
    .clk(clk),.rst(rst),.frame_tick(frame_tick),.trigger(trigger),
    .select_blue(select_blue),.select_red(select_red),.select_sprint(select_sprint),
    .x_in(x),.y_in(y),.de_in(de),.vs_in(vs),.rgb_in(rgb),
    .busy(busy),.de_out(deo),.vs_out(vso),.rgb_out(out));
task step; begin @(posedge clk); #1; end endtask
task frame; begin @(negedge clk);frame_tick=1;step;@(negedge clk);frame_tick=0;step;end endtask
task press; begin @(negedge clk);trigger=1;step;@(negedge clk);trigger=0;step;end endtask
task check; input ok; input [511:0] message; begin if(!ok) begin $display("FAIL: %s",message);$fatal(1);end end endtask
task capture;
    input [1023:0] path;
    integer file_id, px, py;
    begin
        file_id=$fopen(path,"wb");
        $fwrite(file_id,"P6\n1280 720\n255\n");
        for(py=0;py<720;py=py+1)
            for(px=0;px<1280;px=px+1) begin
                @(negedge clk); x=px; y=py; de=1; vs=0;
                repeat(4) step;
                $fwrite(file_id,"%c%c%c",out[23:16],out[15:8],out[7:0]);
            end
        $fclose(file_id);
    end
endtask
integer i,j,f;
initial begin
step;step;@(negedge clk);rst=0;step;
check(!busy,"reset returns idle");
de=1;vs=1; repeat(4) step;
check(deo && vso && out==24'h123456,"idle passthrough and sync");
press;check(busy && dut.state==0,"press queues until frame boundary");
frame;check(dut.state==1 && dut.frame_count==0,"start on frame boundary");
check(!dut.red_selected,"default route remains blue");
repeat(40) frame;
press;check(dut.pending==0,"ignore press during PLAY");
repeat(320) frame;
check(dut.state==2 && dut.frame_count==359 && busy,"360 frames reaches HOLD");
repeat(600) frame;
check(dut.state==2 && dut.frame_count==359 && busy,"HOLD stays indefinitely");
`ifdef EXPORT_FRAME
f=$fopen("doc/hmi_ui/blue_victory_rtl.ppm","wb");
$fwrite(f,"P6\n1280 720\n255\n");
for(j=0;j<720;j=j+1) for(i=0;i<1280;i=i+1) begin
 @(negedge clk);x=i;y=j;de=1;vs=0;
 repeat(3) step;
 $fwrite(f,"%c%c%c",out[23:16],out[15:8],out[7:0]);
end
$fclose(f);
`endif
press;check(dut.state==2,"red page waits frame boundary");
frame;check(dut.state==7 && dut.red_selected && busy,"K2 opens red victory");
repeat(40) frame;
press;check(dut.pending==0,"red playback press ignored");
repeat(320) frame;
check(dut.state==8 && dut.frame_count==359,"red victory holds after 360 frames");
x=100;y=100;repeat(5) step;
check(out[23:16]>out[15:8],"red palette replaces blue backdrop");
`ifdef EXPORT_RED
capture("doc/hmi_ui/red_victory_preview.ppm");
`endif
press;check(dut.state==8,"ranking waits frame boundary");
frame;check(dut.state==3 && busy,"K2 opens eight-runner ranking");
repeat(20) frame;
check(dut.rank_shift[0]<dut.rank_shift[1],"rows slide in one by one");
press;check(dut.pending==0,"ranking-entry press ignored");
repeat(124) frame;
check(dut.state==4 && dut.rank_shift[7]==0,"eight rows settle and hold");
`ifdef EXPORT_RESULTS
capture("doc/hmi_ui/sprint_rank_preview.ppm");
`endif
x=500;y=160;repeat(4) step;
check(out!=24'h123456,"ranking replaces carousel pixels");
press;frame;check(dut.state==5,"K2 opens enlarged top three");
repeat(20) frame;
check(dut.podium_shift[2]<dut.podium_shift[1] &&
      dut.podium_shift[1]<dut.podium_shift[0],"bronze, silver, gold stagger");
press;check(dut.pending==0,"podium-entry press ignored");
repeat(76) frame;
check(dut.state==6 && dut.podium_shift[2]==0,"top three settle and hold");
x=299;y=228;repeat(5) step;
check(out==24'hF7D77A,"gold medal rim visible");
x=299;y=363;repeat(5) step;
check(out==24'hE4EDF2,"silver medal rim visible");
x=299;y=498;repeat(5) step;
check(out==24'hE3AC7B,"bronze medal rim visible");
`ifdef EXPORT_RESULTS
capture("doc/hmi_ui/sprint_podium_preview.ppm");
`endif
press;check(dut.state==6,"return waits frame boundary");
frame;check(dut.state==0 && !busy,"K2 returns to carousel");
repeat(4) step;check(out==24'h123456,"carousel pixels restored");
@(negedge clk);trigger=1;frame_tick=1;step;
@(negedge clk);trigger=0;frame_tick=0;step;
check(dut.state==1 && dut.frame_count==0 && !dut.red_selected,
      "same-cycle trigger restarts from blue");
repeat(359) frame;
press;frame;
check(dut.state==2 && !dut.pending,"last PLAY press does not exit HOLD");
rst=1;step;check(!busy,"reset clears hold");
$display("PASS: blue, red, eight rankings, top three, carousel return, replay");
$finish;
end
initial begin #100000000;$fatal(1,"timeout");end
endmodule
