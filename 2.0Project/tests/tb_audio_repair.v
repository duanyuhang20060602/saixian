`timescale 1ns/1ps
module tb_audio_repair;
reg clk=0,rst=1,clear=0,valid=0,en=0;
reg signed [15:0] li=0,ri=0;
wire signed [15:0] lo,ro;
wire ov;
integer i,outputs=0,prev_l=0,prev_r=0,expected_l,expected_r;
integer path_in,path_out,rc,a,b,c,d,mode;
reg [2047:0] input_name,output_name;
integer dry_queue_l[0:31],dry_queue_r[0:31],q;
integer sample_gap=330;
always #5 clk=~clk;
saixian_audio_repair dut(clk,rst,clear,valid,en,li,ri,lo,ro,ov);
always @(posedge clk) if(ov) outputs=outputs+1;
task sample;
    input integer l,r;
    begin
        @(negedge clk);li=l;ri=r;valid=1;
        @(negedge clk);valid=0;
        repeat(sample_gap) @(negedge clk);
        if(ov!==0) $fatal(1,"valid must be one cycle");
    end
endtask
initial begin
    if($value$plusargs("GAP=%d",sample_gap)) begin
        if(sample_gap<298) $fatal(1,"input spacing below supported 300 clocks");
    end
    repeat(3) @(negedge clk);rst=0;
    if($value$plusargs("INPUT=%s",input_name)) begin
        if(!$value$plusargs("OUTPUT=%s",output_name)) $fatal(1,"OUTPUT required");
        path_in=$fopen(input_name,"r");path_out=$fopen(output_name,"w");
        if(!path_in || !path_out) $fatal(1,"file open failed");
        while(!$feof(path_in)) begin
            rc=$fscanf(path_in,"%d %d %d %d\n",a,b,c,d);
            if(rc==4) begin
                en=c;clear=d;
                if(clear) begin repeat(2) @(negedge clk);clear=0;prev_l=0;prev_r=0;end
                sample(a,b);$fwrite(path_out,"%d %d\n",$signed(lo),$signed(ro));
            end
        end
        $fclose(path_in);$fclose(path_out);
        $display("PASS audio repair vector stream: %0d stereo outputs",outputs);$finish;
    end
    // Exact bypass values, including signed extremes and opposite stereo.
    for(q=0;q<32;q=q+1) begin dry_queue_l[q]=0;dry_queue_r[q]=0;end
    for(i=0;i<1000;i=i+1) begin
        expected_l=dry_queue_l[0];expected_r=dry_queue_r[0];
        prev_l=$signed(16'(i*7919));prev_r=$signed(16'(-i*3571));
        for(q=0;q<31;q=q+1) begin dry_queue_l[q]=dry_queue_l[q+1];dry_queue_r[q]=dry_queue_r[q+1];end
        dry_queue_l[31]=prev_l;dry_queue_r[31]=prev_r;
        sample(prev_l,prev_r);
        if(lo!==16'(expected_l) || ro!==16'(expected_r)) $fatal(1,"dry stereo changed at %d",i);
    end
    // Isolated full-scale pulse is replaced using agreeing zero neighbors.
    clear=1;en=1;repeat(3) @(negedge clk);clear=0;
    repeat(20) sample(0,0);
    sample(30000,-30000);sample(0,0);
    if(lo!=0 || ro!=0) $fatal(1,"isolated click survived");
    repeat(80) begin sample(0,0);if(lo!=0 || ro!=0) $fatal(1,"delayed click survived FIR");end
    // DC is independently rejected in both channels.
    for(i=0;i<24000;i=i+1) sample(5000,-3000);
    if(lo>3 || lo < -3 || ro>3 || ro < -3) $fatal(1,"DC residue %d %d",lo,ro);
    // Reset removes previous track DC/history and clear mutes immediately.
    clear=1;repeat(3) @(negedge clk);
    if(lo!=0 || ro!=0 || ov!=0) $fatal(1,"clear retained old track");
    if(dut.history_samples!=0 || dut.write_index!=0 || dut.state!=0)
        $fatal(1,"clear retained readable RAM history / in-flight work");
    clear=0;en=0;sample(32767,-32768);sample(-32768,32767);
    repeat(270) sample(-32768,32767);
    if(lo!=-32768 || ro!=32767 || dut.wet!=0) $fatal(1,"off did not return to exact bypass");
    // Abort in-flight MAC work; stale physical RAM must remain unreadable.
    clear=1;en=1;repeat(3) @(negedge clk);clear=0;
    @(negedge clk);li=17000;ri=-21000;valid=1;
    @(negedge clk);valid=0;repeat(30) @(negedge clk);
    clear=1;repeat(3) @(negedge clk);clear=0;
    repeat(350) begin @(negedge clk);if(ov || lo!=0 || ro!=0) $fatal(1,"aborted track leaked output");end
    repeat(80) begin sample(0,0);if(lo!=0 || ro!=0) $fatal(1,"stale RAM leaked into new track");end
    $display("PASS audio repair: exact signed stereo bypass, click, DC, reset and crossfade");$finish;
end
initial begin #1000000000;$fatal(1,"timeout");end
endmodule
