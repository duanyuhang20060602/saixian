`timescale 1ns/1ps
module tb_hmi;
reg clk=0;always #5 clk=~clk;reg rst=1,rx=1;
wire prev,next,valid,bad,effect_valid,auto_valid,auto_value;wire [2:0] id,effect_value;wire [7:0] value;
integer pc=0,nc=0,sc=0,bc=0,ec=0,ac=0;
saixian_hmi_uart #(.CLK_FREQ_HZ(1152000)) dut(.clk(clk),.rst(rst),.uart_rx(rx),
 .prev_pulse(prev),.next_pulse(next),.setting_valid(valid),.setting_id(id),.setting_value(value),
 .effect_valid(effect_valid),.effect_value(effect_value),.auto_valid(auto_valid),.auto_value(auto_value),.frame_error_pulse(bad));
always @(posedge clk)begin
 if(prev)pc=pc+1;if(next)nc=nc+1;if(bad)bc=bc+1;
 if(valid)begin sc=sc+1;if(id!=1 || value!=6)$fatal(1,"HMI setting mapping");end
 if(effect_valid)begin ec=ec+1;if(effect_value!=6)$fatal(1,"HMI effect mapping");end
 if(auto_valid)begin ac=ac+1;if(!auto_value)$fatal(1,"HMI auto mapping");end
end
task byte_tx;
 input [7:0] b;integer i;
 begin @(negedge clk);rx=0;repeat(10)@(negedge clk);
 for(i=0;i<8;i=i+1)begin rx=b[i];repeat(10)@(negedge clk);end
 rx=1;repeat(10)@(negedge clk);end
endtask
task command;
 input [7:0] c,v;
 begin byte_tx('h55);byte_tx(c);byte_tx(v);byte_tx(0);byte_tx('hff);byte_tx('hff);byte_tx('hff);repeat(20)@(negedge clk);end
endtask
initial begin
 repeat(5)@(negedge clk);rst=0;
 command(4,0);command(5,0);command('h11,6);command('h18,6);command('h19,1);
 command(4,1); // invalid value must not navigate
 byte_tx('h55);byte_tx(5);repeat(500)@(negedge clk);
 command(5,0);
 if(pc!=1 || nc!=2 || sc!=1 || ec!=1 || ac!=1 || bc<2)$fatal(1,"HMI navigation/parser counts");
 $display("PASS HMI previous/next/settings, invalid value, partial frame and recovery");$finish;
end
initial begin #2000000;$fatal(1,"HMI timeout");end
endmodule
