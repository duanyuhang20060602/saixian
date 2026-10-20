`timescale 1ns/1ps
module tb_touchpad;
reg clk=0;always #5 clk=~clk;
reg rst=1,enable=1,frame=0,valid=0,down=0;reg [9:0] x=0;reg [8:0] y=0;
wire [10:0] cx;wire [9:0] cy;wire click,contact;integer clicks=0;
photo_touchpad #(.CLK_HZ(1000)) dut(.clk(clk),.rst(rst),.enable(enable),.frame_tick(frame),
 .sample_valid(valid),.sample_down(down),.sample_x(x),.sample_y(y),.cursor_x(cx),.cursor_y(cy),.click(click),.contact(contact));
always @(posedge clk)if(click)clicks=clicks+1;
task sample;input [9:0] px;input [8:0] py;input pd;
begin @(negedge clk);x=px;y=py;down=pd;valid=1;@(negedge clk);valid=0;@(negedge clk);end endtask
task latch_frame;begin frame=1;@(negedge clk);frame=0;@(negedge clk);end endtask
initial begin
 repeat(3)@(negedge clk);rst=0;
 sample(100,100,1);repeat(25)@(negedge clk);sample(100,100,0);
 if(clicks!=1)$fatal(1,"tap");
 sample(100,100,1);sample(150,120,1);
 if(cx!=640 || cy!=360)$fatal(1,"frame lock");
 latch_frame;if(cx!=740 || cy!=400)$fatal(1,"relative movement");
 sample(100,100,1);repeat(25)@(negedge clk);sample(100,100,0);
 if(clicks!=1)$fatal(1,"drag returning to origin must not click");
 sample(700,400,1);latch_frame;if(cx!=640 || cy!=360)$fatal(1,"new touch must reanchor");
 sample(0,0,1);latch_frame;if(cx!=0 || cy!=0)$fatal(1,"negative saturation");
 sample(799,479,1);latch_frame;if(cx!=1279 || cy!=719)$fatal(1,"positive saturation");
 sample(799,479,0);if(clicks!=1)$fatal(1,"drag release");
 sample(50,50,1);repeat(190)@(negedge clk);sample(50,50,0);
 if(clicks!=1 || contact)$fatal(1,"lost release timeout");
 sample(50,50,1);sample(50,50,0);if(clicks!=1)$fatal(1,"contact bounce");
 sample(50,50,1);repeat(25)@(negedge clk);enable=0;@(negedge clk);enable=1;sample(50,50,0);
 if(clicks!=1)$fatal(1,"disable cancels contact");
 sample(50,50,1);repeat(100)@(negedge clk);sample(50,50,1);
 repeat(100)@(negedge clk);sample(50,50,1);repeat(100)@(negedge clk);sample(50,50,0);
 if(clicks!=1)$fatal(1,"long press");
 sample(50,50,1);repeat(25)@(negedge clk);sample(50,50,0);
 if(clicks!=2)$fatal(1,"tap recovery");
 $display("PASS touchpad relative motion/reanchor/frame lock/clamping/tap/drag/bounce/long hold/loss/disable");$finish;
end
endmodule
