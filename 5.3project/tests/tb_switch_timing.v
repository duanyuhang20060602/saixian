`timescale 1ns/1ps
module tb_switch_timing;
reg clk=0;always #5 clk=~clk;
reg rst=1,start=0,m1=0,m2=0,finish=0,cancel=0;
wire running,valid;wire [19:0] a,b,c,total;
photo_switch_timing #(.CLK_HZ(10000),.PHASES(3)) dut(clk,rst,start,m1,m2,finish,cancel,running,valid,a,b,c,total);
integer cycles=0,start_cycle=0,mark_cycle=0,first_expected=0,second_expected=0,total_expected=0;
function integer decimal;
 input [19:0] value;
 begin decimal=value[19:16]*10000+value[15:12]*1000+value[11:8]*100+value[7:4]*10+value[3:0];end
endfunction
always @(posedge clk)begin
 cycles=cycles+1;
 if(start)begin start_cycle=cycles;mark_cycle=cycles;end
 else if(running && !cancel)begin
  if(m1)begin first_expected=(cycles-start_cycle)/10;mark_cycle=cycles;end
  if(m2)begin second_expected=(cycles-start_cycle)/10-(mark_cycle-start_cycle)/10;mark_cycle=cycles;end
  if(finish)begin
   total_expected=(cycles-start_cycle)/10;
   #1;
   if(!valid || running || decimal(a)!=first_expected || decimal(b)!=second_expected ||
      decimal(c)!=total_expected-first_expected-second_expected || decimal(total)!=total_expected)
    $fatal(1,"timing differs from independent cycle timestamps: %h %h %h %h",a,b,c,total);
  end
 end
end
task pulse_start;begin @(negedge clk);start=1;@(negedge clk);start=0;end endtask
task sample;
 input integer wait1,wait2,wait3;
 begin
  pulse_start();repeat(wait1)@(negedge clk);m1=1;@(negedge clk);m1=0;
  repeat(wait2)@(negedge clk);m2=1;@(negedge clk);m2=0;
  repeat(wait3)@(negedge clk);finish=1;@(negedge clk);finish=0;
 end
endtask
wire [5:0] sel;wire [7:0] seg;
photo_switch_timing_display #(.CLK_HZ(6000),.PAGES(4)) display_dut(.clk(clk),.rst(rst),.running(running),
 .first_ms(20'h01234),.second_ms(20'h00567),.third_ms(20'h00089),.total_ms(20'h01890),.seg_sel(sel),.seg_data(seg));
reg [79:0] saved;
initial begin
 repeat(3)@(negedge clk);rst=0;
 sample(29,50,119); // decimal carry and marks exactly on ms boundaries
 sample(0,0,0); // sub-ms phases report zero
 sample(98,102,9);
 saved={a,b,c,total};pulse_start();repeat(35)@(negedge clk);cancel=1;
 @(negedge clk);cancel=0;finish=1;@(negedge clk);finish=0;
 if(running || {a,b,c,total}!==saved)$fatal(1,"cancel replaced last successful result");
 // A new request restarts its own clock and discards the earlier partial sample.
 pulse_start();repeat(101)@(negedge clk);sample(5,11,22);
 wait(display_dut.page==3);repeat(12)@(negedge clk);
 if(display_dut.digits!==24'h098104)$fatal(1,"page 4 or decimal digit order wrong: %h",display_dut.digits);
 // Exhaust the public counter to exercise all five decimal digits and saturation.
 @(negedge clk);start=1;@(negedge clk);start=0;
 repeat(1000010)@(negedge clk);
 if(dut.elapsed!==20'h99999)$fatal(1,"counter did not saturate at 99999 ms");
 $display("PASS timing: independent cycle reference, carries, sub-ms marks, atomic results, cancel, restart, page 4, saturation");
 $finish;
end
initial begin #20000000;$fatal(1,"timing test timeout");end
endmodule
