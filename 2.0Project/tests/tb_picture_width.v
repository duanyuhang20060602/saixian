`timescale 1ns/1ps
module tb_picture_width;
reg clk=0;always #5 clk=~clk;
reg rst=1;reg [23:0] rgb=0;
reg [3:0] b=0,c=0,s=0;
wire [23:0] compact,reference;
saixian_picture_adjust_pipe dut(clk,rst,1'b1,11'd0,rgb,b,c,s,2'd0,compact);
saixian_picture_adjust wide(clk,rst,1'b1,10'd0,rgb,b,c,s,2'd0,reference);
integer ib,ic,is,n,count=0;
initial begin
    repeat(4) @(negedge clk);rst=0;
    for(ib=0;ib<9;ib=ib+1) for(ic=0;ic<9;ic=ic+1) for(is=0;is<9;is=is+1) begin
        b=ib;c=ic;s=is;
        for(n=0;n<64;n=n+1) begin
            rgb={8'(n*4),8'(n*57),8'(n*101)};
            repeat(11) @(negedge clk);
            if(compact!==reference) $fatal(1,"width optimization changed RGB %h b=%d c=%d s=%d compact=%h ref=%h",rgb,b,c,s,compact,reference);
            count=count+1;
        end
    end
    $display("PASS conservative 11-bit manual adjustment versus retained wide reference: %d cases",count);
    $finish;
end
endmodule
