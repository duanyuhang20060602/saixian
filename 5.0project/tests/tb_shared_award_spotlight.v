`timescale 1ns/1ps
module tb;
reg clk=0,rst=1;always #5 clk=~clk;
reg[7:0]a=0,b=0,phase=0,q=0;reg valid=0;reg[23:0]color=0;
wire[23:0]rgb,ref_rgb;wire de,vs,ref_de,ref_vs;
photo_spotlight_player #(.SHARED_CACHE(1)) dut(.mem_clk(clk),.mem_rst(rst),.enable(1'b0),.base(21'd0),.stream_ack(1'b0),.data(32'd0),.data_valid(1'b0),.video_clk(clk),.video_rst(rst),.display_valid(1'b1),.pause(1'b0),.rgb_in(color),.de_in(valid),.vs_in(1'b0),.rgb_out(rgb),.de_out(de),.vs_out(vs),.cache_read_data(32'd0));
photo_spotlight_player_before #(.SHARED_CACHE(1)) reference(.mem_clk(clk),.mem_rst(rst),.enable(1'b0),.base(21'd0),.stream_ack(1'b0),.data(32'd0),.data_valid(1'b0),.video_clk(clk),.video_rst(rst),.display_valid(1'b1),.pause(1'b0),.rgb_in(color),.de_in(valid),.vs_in(1'b0),.rgb_out(ref_rgb),.de_out(ref_de),.vs_out(ref_vs),.cache_read_data(32'd0));
integer i,j,k,checks=0;reg[4:0]valid_bits=0;
always @(posedge clk)begin #1;
 if({rgb,de,vs,dut.field4}!=={ref_rgb,ref_de,ref_vs,reference.field4})$fatal(1,"temporal interpolation mismatch a=%d b=%d phase=%d actual=%h/%d old=%h/%d",a,b,phase,rgb,dut.field4,ref_rgb,reference.field4);
 checks=checks+1;
end
initial begin
 repeat(4)@(negedge clk);rst=0;
 force dut.spatial2a=a;force reference.spatial2a=a;
 force dut.spatial2b=b;force reference.spatial2b=b;
 force dut.phase1=phase;force reference.phase1=phase;
 force dut.quant_coord=q;force reference.quant_coord=q;
 force dut.valid_pipe=valid_bits;force reference.valid_pipe=valid_bits;
 for(k=0;k<4;k=k+1)for(i=0;i<256;i=i+1)for(j=0;j<256;j=j+1)begin
  a=i;b=k==0 ? 0:k==1 ? 255:k==2 ? 255-i:(i*71+j*7)%256;phase=j;q=(i*19+j*13+k*61)%256;valid=1;valid_bits=31;color=$random;@(negedge clk);
 end
 for(i=0;i<30000;i=i+1)begin a=$random;b=$random;phase=$random;q=$random;valid=i[0];valid_bits=valid ? 31:0;rst=i%1031==0;color=$random;@(negedge clk);end
 $display("PASS exact one-product interpolation: %0d same-cycle field/RGB/sync comparisons, all phases and endpoint fields, positive/negative slopes, dither, invalid input and reset",checks);$finish;
end
endmodule
