`timescale 1ns/1ps
module tb_enhance_detail;
reg clk=0;always #5 clk=~clk;
reg rst=1,de=0;reg [10:0] x=0;reg [9:0] y=0;
reg [23:0] rgb=0;reg [1:0] strength=0;
wire [23:0] out;wire od,ov;wire [10:0] ox;wire [9:0] oy;wire [1:0] gain;
saixian_adaptive_enhance #(.WIDTH(64)) dut(clk,rst,de,1'b0,1'b0,1'b0,x,y,rgb,2'd1,strength,out,od,ov,ox,oy,gain);
integer expect_pixel=0,expected[0:6],i,j,s,k,a,b,total,d,dt,e,dx,dy,checks=0;
reg [6:0] valid=0;
function integer level;
    input integer px,py;
    begin level=(px<32 ? 40 : 180)+((px*7+py*11)%31)-15;end
endfunction
always @(posedge clk) if(!rst) begin
    for(k=6;k>0;k=k-1) expected[k]=expected[k-1];
    expected[0]=expect_pixel;valid={valid[5:0],de};
    #1;
    if(od!==valid[6]) $fatal(1,"detail DE alignment");
    if(od) begin
        if(out !== {8'(expected[6]),8'(expected[6]),8'(expected[6])})
            $fatal(1,"detail reference mismatch x=%d y=%d strength=%d got=%h expected=%d",ox,oy,strength,out,expected[6]);
        checks=checks+1;
    end
end
initial begin
    repeat(4) @(negedge clk);rst=0;
    for(s=0;s<4;s=s+1) begin
        strength=s;
        for(j=0;j<12;j=j+1) begin
            for(i=0;i<64;i=i+1) begin
                a=level(i,j);total=8*a;
                for(dy=0;dy<3;dy=dy+1) for(dx=0;dx<3;dx=dx+1)
                    if(dx!=0 || dy!=0) begin
                        b=(i>=dx && j>=dy) ? level(i-dx,j-dy) : a;
                        if((b-a)>24 || (a-b)>24) b=a;
                        total=total+b;
                    end
                d=a-(total>>4);
                if(d>=-3 && d<=3) dt=0;
                else case(s) 0:dt=0;1:dt=d>>>1;2:dt=d;3:dt=d+(d>>>1);endcase
                if(dt>12) dt=12;if(dt< -12) dt=-12;
                e=a+((a*(255-a))>>10)+dt;
                if(e<0) e=0;if(e>255) e=255;
                @(negedge clk);de=1;x=i;y=j;rgb={8'(a),8'(a),8'(a)};expect_pixel=e;
            end
            @(negedge clk);de=0;repeat(8) @(negedge clk);
        end
        repeat(10) @(negedge clk);
    end
    if(checks!=3072) $fatal(1,"detail count %d",checks);
    $display("PASS independent integer reference: range-gated causal 3x3, four strengths, edges, detail clamp (%d pixels)",checks);
    $finish;
end
endmodule
