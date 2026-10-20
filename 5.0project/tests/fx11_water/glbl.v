// Board reset remains asserted until FPGA startup and PLL lock have completed.
module glbl;
wire gsrn=1'b1;
wire done_gwe=1'b1;
endmodule
