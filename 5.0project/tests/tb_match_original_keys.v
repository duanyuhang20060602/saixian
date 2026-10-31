`timescale 1ns/1ps
module tb_match_keys;
reg clk=0;always #5 clk=~clk;
reg rst=1;reg [3:0] keys=15;reg [2:0] key_scene=0;wire [3:0] s,l;
match_keys #(.CLK_HZ(100),.DB_CYCLES(3),.HOLD_CYCLES(40)) d(clk,rst,keys,key_scene,s,l);
integer shorts=0,longs=0;
always @(posedge clk)begin #1;if(s[0])shorts=shorts+1;if(l[0])longs=longs+1;end
task cycles;input integer n;begin repeat(n)@(negedge clk);end endtask
initial begin
 cycles(3);rst=0;cycles(10);
 keys[0]=0;cycles(1);keys[0]=1;cycles(10);
 if(shorts!=0 || longs!=0)$fatal(1,"bounce emitted");
 keys[0]=0;cycles(15);keys[0]=1;cycles(10);
 if(shorts!=1 || longs!=0)$fatal(1,"short");
 keys[0]=0;cycles(65);keys[0]=1;cycles(10);
 if(shorts!=1 || longs!=1)$fatal(1,"long emitted release short");
 keys[0]=0;cycles(15);key_scene=2;cycles(60);keys[0]=1;cycles(10);
 if(shorts!=1 || longs!=1)$fatal(1,"key_scene leaked held gesture");
 keys[0]=0;cycles(15);keys[0]=1;cycles(10);
 if(shorts!=2)$fatal(1,"not rearmed");
 $display("PASS keys: debounce, short, one-shot long, key_scene consumption and rearm");$finish;
end
endmodule
