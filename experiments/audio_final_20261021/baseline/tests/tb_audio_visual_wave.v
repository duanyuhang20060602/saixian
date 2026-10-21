`timescale 1ns/1ps
module tb_audio_visual_wave;
reg clk=0,rst=1,frame_tick=0,sample_valid=0;
reg signed [15:0] left=0,right=0;
reg [7:0] read_index=0;
wire [31:0] read_extrema;
wire valid;
integer i,j;
integer a,b,al,bl,amin,amax,bmin,bmax;
reg [31:0] sine_expected[0:255];
reg [31:0] saved;
always #5 clk=~clk;
saixian_av_wave dut(.*);
task sample;input signed [15:0] a,b;begin
    left=a;right=b;sample_valid=1;@(negedge clk);sample_valid=0;@(negedge clk);
end endtask
task publish;begin frame_tick=1;@(negedge clk);frame_tick=0;repeat(3) @(negedge clk);end endtask
initial begin
    repeat(3) @(negedge clk);rst=0;
    // Silence must timeout, then capture exactly 1024 samples.
    for(i=0;i<2048;i=i+1) sample(0,0);
    if(valid || !dut.pending) $fatal(1,"silence timeout/publication");
    publish;if(!valid || read_extrema!==0) $fatal(1,"silent line");
    sample(-1024,0);sample(1024,0);
    for(i=1;i<1024;i=i+1) begin
        if(i%4==1) sample(32767,-32768);
        else if(i%4==2) sample(-32768,32767);
        else sample(0,0);
    end
    if(!dut.pending || read_extrema!==0) $fatal(1,"capture modified displayed bank");
    publish;
    for(j=0;j<256;j=j+1) begin
        read_index=j;repeat(3) @(negedge clk);
        if(read_extrema!==32'h807f807f) $fatal(1,"extrema %d %h",j,read_extrema);
    end
    saved=read_extrema;
    for(i=0;i<2048;i=i+1) sample(0,0);
    if(read_extrema!==saved) $fatal(1,"display torn before frame");
    publish;if(read_extrema!==0) $fatal(1,"new silence not published");
    sample(-1024,0);sample(1024,0);
    amin=4;amax=4;bmin=0;bmax=0;
    for(i=1;i<1024;i=i+1) begin
        a=$rtoi(20000.0*$sin(6.283185307179586*i/64.0));b=-a;
        al=a>>>8;bl=b>>>8;
        if(i%4==0) begin amin=al;amax=al;bmin=bl;bmax=bl;end
        else begin
            if(al<amin) amin=al;if(al>amax) amax=al;
            if(bl<bmin) bmin=bl;if(bl>bmax) bmax=bl;
        end
        if(i%4==3) sine_expected[i/4]={amin[7:0],amax[7:0],bmin[7:0],bmax[7:0]};
        sample(a,b);
    end
    publish;
    for(j=0;j<256;j=j+1) begin
        read_index=j;repeat(3) @(negedge clk);
        if(read_extrema!==sine_expected[j]) $fatal(1,"sine stereo extrema mismatch %d",j);
    end
    $display("PASS stereo min/max, impulse/fullscale, trigger and timeout, 1024-sample window, frame-atomic banks and silence");$finish;
end
endmodule
