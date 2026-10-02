`timescale 1ns/1ps
module tb_audio_visual_fft;
reg clk=0,rst=1,frame_tick=0,sample_valid=0;
reg signed [15:0] left=0,right=0;
reg [4:0] read_band=0;
wire [6:0] read_height,read_peak;
wire valid,block_done;
reg [31:0] stimulus[0:1023];
reg [1023:0] stimulus_path,output_path;
integer fout,i,cycles=0,interval=256;
reg [6:0] expected_heights[0:31];
always #5 clk=~clk;
saixian_av_fft dut(.*);
always @(posedge clk) begin
    cycles=cycles+1;
    if(cycles>1100000) $fatal(1,"FFT timeout state=%d band=%d bin=%d",dut.state,dut.band,dut.energy_index);
    if(!rst && dut.state==23) $fdisplay(fout,"BIN %0d %0d %0d",dut.channel,dut.energy_index,dut.bin_energy);
    if(!rst && dut.state==32) expected_heights[dut.band]=dut.target_height;
end
initial begin
    if(!$value$plusargs("STIM=%s",stimulus_path)) $fatal(1,"missing STIM");
    if(!$value$plusargs("OUT=%s",output_path)) $fatal(1,"missing OUT");
    if($value$plusargs("INTERVAL=%d",interval)) begin end
    $readmemh(stimulus_path,stimulus);fout=$fopen(output_path,"w");
    repeat(4) @(negedge clk);rst=0;
    for(i=0;i<1024;i=i+1) begin
        left=stimulus[i][15:0];right=stimulus[i][31:16];sample_valid=1;
        @(negedge clk);sample_valid=0;repeat(interval-1) @(negedge clk);
    end
    wait(block_done);@(negedge clk);
    for(i=0;i<32;i=i+1) $fdisplay(fout,"BAND %0d %0d",i,expected_heights[i]);
    frame_tick=1;@(negedge clk);frame_tick=0;repeat(150) @(negedge clk);
    // A second frame updates the display from the complete published target.
    frame_tick=1;@(negedge clk);frame_tick=0;repeat(150) @(negedge clk);
    if(!valid) $fatal(1,"publication missing");
    for(i=0;i<32;i=i+1) begin
        read_band=i;repeat(3) @(negedge clk);
        if(read_height!==expected_heights[i]) $fatal(1,"read-side alignment");
    end
    $fclose(fout);$display("PASS FFT block, both stereo channels, coherent publication and synchronous band reads");$finish;
end
endmodule
