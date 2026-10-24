`timescale 1ns/1ps
module tb;
reg clk=0;always #5 clk=~clk;reg rst=1,rx=1;
wire mode_valid,mode_value,bad,next_page;
integer legacy=0,relief=0,errors=0,navigations=0;
reg previous_valid=0;
saixian_hmi_uart #(.CLK_FREQ_HZ(1152000)) dut(.clk(clk),.rst(rst),.uart_rx(rx),
 .award_mode_valid(mode_valid),.award_mode_value(mode_value),.next_pulse(next_page),.frame_error_pulse(bad));
always @(posedge clk)if(!rst)begin
 if(mode_valid)begin
  if(previous_valid)$fatal(1,"mode command pulse lasted more than one cycle");
  if(mode_value)relief=relief+1;else legacy=legacy+1;
 end
 previous_valid=mode_valid;
 if(bad)errors=errors+1;
 if(next_page)navigations=navigations+1;
end
task byte_tx;input[7:0] b;integer i;begin
 @(negedge clk);rx=0;repeat(10)@(negedge clk);
 for(i=0;i<8;i=i+1)begin rx=b[i];repeat(10)@(negedge clk);end
 rx=1;repeat(10)@(negedge clk);
end endtask
task command;input[7:0] c,v;begin
 byte_tx('h55);byte_tx(c);byte_tx(v);byte_tx(0);byte_tx('hff);byte_tx('hff);byte_tx('hff);repeat(20)@(negedge clk);
end endtask
initial begin
 repeat(5)@(negedge clk);rst=0;
 command('h32,0);command('h32,1);command('h32,1);command('h32,0);
 if(legacy!=2 || relief!=2 || errors!=0)$fatal(1,"valid award-mode command mapping");
 command('h32,2);command('h32,255);
 // Corrupt the reserved byte, then recover without resetting the receiver.
 byte_tx('h55);byte_tx('h32);byte_tx(1);byte_tx(1);byte_tx('hff);byte_tx('hff);byte_tx('hff);
 repeat(500)@(negedge clk);
 // Corrupt the trailer, then leave a partial command to exercise timeout.
 byte_tx('h55);byte_tx('h32);byte_tx(1);byte_tx(0);byte_tx('hff);byte_tx(0);byte_tx('hff);
 byte_tx('h55);byte_tx('h32);repeat(500)@(negedge clk);
 if(legacy!=2 || relief!=2 || errors<5)$fatal(1,"invalid mode frame acted or missing rejection");
 command(5,0);command('h32,1);
 if(legacy!=2 || relief!=3 || navigations!=1)$fatal(1,"mode parser recovery/legacy navigation");
 $display("PASS HMI 0x32 old/new mode mapping, one-cycle pulses, invalid values, reserved byte/trailer rejection, partial-frame timeout and recovery");$finish;
end
initial begin #3000000;$fatal(1,"mode HMI timeout");end
endmodule
