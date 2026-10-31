`timescale 1ns/1ps
module tb_pitch;
reg clk=0,rst=1,clear=0,sample_valid=0;
reg signed [15:0] left_in=0,right_in=0;
reg [2:0] requested_mode=0;
wire signed [15:0] left_out,right_out;
wire out_valid,ready,overrun;wire [2:0] active_mode;
reg [31:0] stimulus[0:9999];reg [2:0] modes[0:9999];
reg [8191:0] stimulus_path,mode_path,output_path;
integer f,i,count=0,cycles=0,started=0,max_latency=0,busy_cycles=0,max_busy=0;
reg signed [8:0] previous_a=0,previous_b=0;
reg reset_test=0;
always #5 clk=~clk;
saixian_audio_pitch #(.COMPACT_DRY(1)) dut(.*);
always @(posedge clk) begin
    cycles=cycles+1;if(sample_valid)started=cycles;
    if(dut.state!=0)busy_cycles=busy_cycles+1;
    else begin if(busy_cycles>max_busy)max_busy=busy_cycles;busy_cycles=0;end
    if(busy_cycles>=699)$fatal(1,"background search missed sample deadline");
end
always @(negedge clk) begin
    if(!rst && !clear && requested_mode==active_mode && dut.wet_gain!=0) begin
        if(dut.offset_a!=previous_a && !dut.mute_a)$fatal(1,"audible A pointer changed");
        if(dut.offset_b!=previous_b && !dut.mute_b)$fatal(1,"audible B pointer changed");
    end
    previous_a=dut.offset_a;previous_b=dut.offset_b;
end
always @(negedge clk) if(out_valid) begin
    if(overrun) $fatal(1,"pitch overrun");
    if(cycles-started>max_latency)max_latency=cycles-started;
    if(reset_test) begin if(left_out!==0 || right_out!==0)$fatal(1,"stale history after clear");end
    else begin
        $fdisplay(f,"%0d %0d %0d %0d %0d %0d",left_out,right_out,active_mode,dut.wet_gain,dut.phase,ready);
        count=count+1;
    end
end
task send;
input [31:0] word;input [2:0] mode;
begin
    left_in=word[15:0];right_in=word[31:16];requested_mode=mode;sample_valid=1;
    @(negedge clk);sample_valid=0;repeat(699)@(negedge clk);
end endtask
initial begin
    if(!$value$plusargs("STIM=%s",stimulus_path))$fatal(1,"STIM");
    if(!$value$plusargs("MODES=%s",mode_path))$fatal(1,"MODES");
    if(!$value$plusargs("OUT=%s",output_path))$fatal(1,"OUT");
    $readmemh(stimulus_path,stimulus);$readmemh(mode_path,modes);f=$fopen(output_path,"w");
    repeat(5)@(negedge clk);rst=0;
    for(i=0;i<10000;i=i+1)send(stimulus[i],modes[i]);
    if(count!=10000 || !ready || overrun)$fatal(1,"count/ready %d",count);
    clear=1;@(negedge clk);clear=0;reset_test=1;
    if(ready || out_valid || dut.fill!=0)$fatal(1,"clear failed");
    for(i=0;i<2400;i=i+1)send(0,0);
    if(!ready || overrun)$fatal(1,"zero recovery failed");
    $fclose(f);$display("PASS 10000 stereo pitch samples, all five modes, clear removes stale RAM; output %0d clocks, total work %0d clocks/sample",max_latency,max_busy);$finish;
end
endmodule
