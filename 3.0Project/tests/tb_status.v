`timescale 1ns/1ps
module tb_status;
reg clk=0;always #5 clk=~clk;
reg rst=1;reg [2:0] sd=0,stage=0;reg [3:0] mem=0,player=0;reg underflow=0;
wire [5:0] sel;wire [7:0] data;
reg mode=0,key_n=1;reg [191:0] bundle=192'h11223344_55667788_99aabbcc_ddeeff00_12345678_abcdef01;
delta_status #(.KEY_DEBOUNCE(4),.SECOND_TICKS(4)) dut(clk,rst,sd,stage,mem,player,underflow,sel,data,mode,key_n,bundle);
task check;input [7:0] code;begin repeat(4)@(negedge clk);if(dut.code!==code)$fatal(1,"status code got=%h want=%h",dut.code,code);end endtask
initial begin
 repeat(4)@(negedge clk);rst=0;check(0);
 sd=1;stage=2;check(8'h11);if(dut.stage!=2)$fatal;
 mem=7;player=9;underflow=1;check(8'h11);
 sd=0;check(8'h27);mem=0;check(8'h39);player=0;check(8'h40);underflow=0;check(0);
 mem=10;check(8'h2a);mem=15;check(8'h2f);
 mode=1;repeat(5)@(negedge clk);
 if(dut.page!=0 || dut.value!=16'h3344)$fatal(1,"expected CRC low page");
 key_n=0;repeat(2)@(negedge clk);key_n=1;repeat(6)@(negedge clk);
 if(dut.page!=0)$fatal(1,"key bounce advanced page");
 key_n=0;repeat(12)@(negedge clk);
 if(dut.page!=1 || dut.value!=16'h1122)$fatal(1,"expected CRC high page or repeated held-key advance");
 key_n=1;repeat(9)@(negedge clk);key_n=0;repeat(9)@(negedge clk);
 if(dut.page!=2 || dut.value!=16'hef01)$fatal(1,"upload CRC low page");
 force dut.page=4;#1;if(dut.value!=16'h5678)$fatal;
 force dut.page=6;#1;if(dut.value!=16'hff00)$fatal;
 force dut.page=8;#1;if(dut.value!=16'hbbcc)$fatal;
 force dut.page=10;#1;if(dut.value!=16'h7788)$fatal;
 force dut.page=11;#1;if(dut.value!=16'h5566)$fatal;release dut.page;
 mode=0;repeat(5)@(negedge clk);if(dut.page!=0)$fatal;
 rst=1;repeat(3)@(negedge clk);mem=13;rst=0;check(8'h2d);
 wait(dut.fault_second==5);@(negedge clk);
 if(!dut.show_debug || dut.shown_page!=6 || dut.value!=16'hff00)$fatal(1,"automatic BIST fault pages need SW2/KEY1");
 wait(dut.fault_second==10);@(negedge clk);if(dut.shown_page!=11 || dut.value!=16'h5566)$fatal;
 wait(dut.fault_second==0);@(negedge clk);if(dut.show_debug)$fatal(1,"automatic fault code not restored");
 mem=9;check(8'h29);wait(dut.fault_second==5);@(negedge clk);
 if(dut.shown_page!=0 || dut.value!=16'h3344)$fatal(1,"automatic CRC pages wrong");
 mem=0;player=3;check(8'h33);wait(dut.fault_second==5);@(negedge clk);
 if(dut.shown_page!=6 || dut.value!=16'hff00)$fatal(1,"decoder fault pages wrong");
 player=7;check(8'h37);wait(dut.fault_second==5);@(negedge clk);
 if(dut.shown_page!=0)$fatal(1,"stream CRC pages wrong");
 $display("PASS diagnostic: fault priority, E11/E27/E39/E40/E2A/E2F, CRC/mismatch pages, key debounce, held key and exit reset; automatic E2D/E29 pages without SW2 or KEY1");$finish;
end
endmodule
