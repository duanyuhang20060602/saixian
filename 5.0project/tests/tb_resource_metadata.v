`timescale 1ns/1ps
// Exercise real analysis, real four-bank publication, and native RAM wiring.
module tb_resource_metadata;
reg clk=0,rst=1;always #5 clk=~clk;
reg pcm_sent=0,snapshot=0;reg [31:0] pcm=0;reg [8:0] address=0;
wire [31:0] data;
photo_av_metadata_b #(.EDGE_METADATA(1)) b(clk,rst,pcm_sent,snapshot,pcm,address,data);
reg tick=0,begin_packet=0,word_valid=0,commit=0,finish=0;
reg [31:0] play_position=0,word_data=0;reg [8:0] word_index=0;
wire available,fft_valid,wave_valid;wire [7:0] target;
wire [6:0] height,peak;wire [31:0] extrema;
photo_av_metadata_a #(.EDGE_METADATA(1)) a(.clk(clk),.rst(rst),.frame_tick(tick),.play_position(play_position),
 .begin_packet(begin_packet),.word_valid(word_valid),.commit_packet(commit),.finish_packet(finish),
 .word_index(word_index),.word_data(word_data),.available(available),.read_band(5'd0),.read_index(8'd0),
 .height(height),.peak(peak),.extrema(extrema),.fft_valid(fft_valid),.wave_valid(wave_valid),.edge_target(target));
integer reference_envelope=0,mono,mag,i,j,checks=0;reg [31:0] random_state=32'h27c7813b;
reg [31:0] header,sample_position;reg [7:0] expected_target;
task sample;input signed [15:0] l,r;begin
 @(negedge clk);pcm={r,l};pcm_sent=1;
 mono=($signed(l)+$signed(r))>>>1;mag=mono<0 ? -mono:mono;
 if(mag>reference_envelope)reference_envelope=reference_envelope+((mag-reference_envelope)>>6);
 else reference_envelope=reference_envelope-((reference_envelope-mag)>>10);
 @(negedge clk);pcm_sent=0;
 if(b.edge_envelope!==19'(reference_envelope))$fatal(1,"B envelope arithmetic mismatch");
 checks=checks+1;
end endtask
task snap;begin
 @(negedge clk);snapshot=1;@(negedge clk);snapshot=0;
 address=0;#1;header=data;address=1;#1;sample_position=data;
 if(header[31:16]!==16'h4132 || header[15:8]!==8'(reference_envelope>8191 ? 255:reference_envelope>>5))
  $fatal(1,"AV2 snapshot header mismatch %h",header);
end endtask
task word;input [8:0] index;input [31:0] value;begin
 @(negedge clk);word_index=index;word_data=value;word_valid=1;
 @(negedge clk);word_valid=0;
end endtask
task packet;input [31:0] h,p;input ok;begin
 wait(available);@(negedge clk);begin_packet=1;@(negedge clk);begin_packet=0;
 word(0,h);word(1,p);
 // Sparse write patterns exercise both independently clocked cache ports.
 word(2,32'h00001a35);word(34,32'hca174f61);
 @(negedge clk);commit=ok;finish=1;@(negedge clk);finish=0;commit=0;
end endtask
task frame;begin
 repeat(5)@(negedge clk);tick=1;@(negedge clk);tick=0;repeat(2)@(negedge clk);
end endtask
initial begin
 repeat(5)@(negedge clk);rst=0;
 // Signed extremes, antiphase, attack and release, then randomized stereo.
 sample(-32768,-32768);sample(32767,32767);sample(-32768,32767);
 for(i=0;i<18000;i=i+1)begin
  random_state={random_state[30:0],random_state[31]^random_state[21]^random_state[1]^random_state[0]};
  if(i<2048)sample(24000,20000);
  else if(i<8192)sample(0,0);
  else sample(random_state[15:0],random_state[31:16]);
 end
 snap();expected_target=header[15:8];packet(header,sample_position,1);
 play_position=sample_position-1;frame();if(target!=0 || fft_valid || wave_valid)$fatal(1,"future audio published");
 play_position=sample_position;frame();if(target!==expected_target)$fatal(1,"eligible envelope not published");
 // A failed transport CRC cannot replace the displayed amplitude.
 packet({16'h4132,8'd7,8'd3},sample_position,0);frame();
 if(target!==expected_target)$fatal(1,"failed CRC published envelope");
 // A CRC pulse without both header words must not publish a partially
 // overwritten bank; the previous scene stays visible.
 wait(available);@(negedge clk);begin_packet=1;@(negedge clk);begin_packet=0;
 word(0,{16'h4132,8'd9,8'd3});
 @(negedge clk);commit=1;finish=1;@(negedge clk);commit=0;finish=0;frame();
 if(target!==expected_target)$fatal(1,"incomplete metadata header published");
 // Two future snapshots can arrive before the next frame; publish newest
 // eligible one, then retain the later one until playback catches it.
 packet({16'h4132,8'd31,8'd3},sample_position+10,1);
 packet({16'h4132,8'd47,8'd3},sample_position+20,1);
 play_position=sample_position+10;frame();if(target!==31)$fatal(1,"snapshot ordering/eligibility failed");
 play_position=sample_position+20;frame();if(target!==47)$fatal(1,"future snapshot lost");
 // Wrap the short generation tags many times without future publication.
 for(j=0;j<520;j=j+1)begin
  packet({16'h4132,8'(j),8'd3},sample_position+21+j,1);
  play_position=sample_position+21+j;frame();
  if(target!==8'(j) || !fft_valid || !wave_valid)$fatal(1,"generation wrap failed at %0d",j);
  if({peak,height}!==14'h1a35 || extrema!==32'hca174f61)$fatal(1,"wave/band data changed");
 end
 // Fill all three non-display banks. A rejected fourth begin cannot
 // overwrite the displayed or pending bank; publishing frees storage.
 packet({16'h4132,8'd51,8'd3},sample_position+1000,1);
 packet({16'h4132,8'd61,8'd3},sample_position+1010,1);
 packet({16'h4132,8'd71,8'd3},sample_position+1020,1);
 if(available)$fatal(1,"metadata backpressure missing");
 @(negedge clk);begin_packet=1;@(negedge clk);begin_packet=0;
 word(0,{16'h4132,8'd99,8'd3});word(1,play_position);
 @(negedge clk);commit=1;finish=1;@(negedge clk);commit=0;finish=0;
 play_position=sample_position+1000;frame();if(target!==51 || !available)$fatal(1,"full-cache bank protection failed");
 play_position=sample_position+1020;frame();if(target!==71)$fatal(1,"newest eligible snapshot selection failed");
 // Playback positions are modular 32-bit sample counters.
 play_position=32'hfffffff0;packet({16'h4132,8'd81,8'd3},32'hfffffff8,1);
 frame();if(target!==71)$fatal(1,"future snapshot published before position wrap");
 play_position=32'h00000004;frame();if(target!==81)$fatal(1,"position wrap lost eligible snapshot");
 // Reset invalidates all cached epochs, including stale high amplitude.
 @(negedge clk);rst=1;@(negedge clk);rst=0;frame();
 if(target!=0 || fft_valid || wave_valid)$fatal(1,"stale metadata survived reset");
 $display("PASS B envelope: %0d stereo samples; AV2 header; CRC rejection; playback eligibility; four-bank ordering; 520 generations; native FFT/wave RAM; reset",checks);
 $finish;
end
initial begin #20000000;$fatal(1,"metadata timeout");end
endmodule
