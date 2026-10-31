`timescale 1ns/1ps
module tb;
reg clk=0,rst=1,tick=0;always #5 clk=~clk;
reg[3:0] event_code=0,style=0;wire[63:0] got0,got1,want0,want1;
photo_audio_cue_candidate #(.PAGE_STYLES(0)) a0(clk,rst,event_code,style,tick,got0[63],got0[62:39],got0[38:15],got0[14:7],got0[6],got0[5],got0[4:0]);
photo_audio_cue_reference #(.PAGE_STYLES(0)) b0(clk,rst,event_code,style,tick,want0[63],want0[62:39],want0[38:15],want0[14:7],want0[6],want0[5],want0[4:0]);
photo_audio_cue_candidate #(.PAGE_STYLES(1)) a1(clk,rst,event_code,style,tick,got1[63],got1[62:39],got1[38:15],got1[14:7],got1[6],got1[5],got1[4:0]);
photo_audio_cue_reference #(.PAGE_STYLES(1)) b1(clk,rst,event_code,style,tick,want1[63],want1[62:39],want1[38:15],want1[14:7],want1[6],want1[5],want1[4:0]);
integer cycles=0,samples=0,i,j,n;
always @(negedge clk)begin
 cycles=cycles+1;
 if(!rst && (got0!==want0 || got1!==want1))$fatal(1,"cue mismatch cycle %d event %d style %d got %h/%h want %h/%h",cycles,event_code,style,got0,got1,want0,want1);
end
task fire;input[3:0] code;begin @(negedge clk);tick=0;event_code=code;@(negedge clk);event_code=0;end endtask
task sample;begin @(negedge clk);tick=1;@(negedge clk);tick=0;repeat(14)@(negedge clk);samples=samples+1;end endtask
initial begin
 repeat(5)@(negedge clk);rst=0;
 for(i=0;i<11;i=i+1)begin style=i;fire(6);for(j=0;j<6000;j=j+1)sample;end
 for(i=1;i<16;i=i+1)begin fire(i);n=0;while((want0[6] || want1[6]) && n<100000)begin sample;n=n+1;end if(want0[6] || want1[6])$fatal(1,"cue duration runaway");end
 for(i=0;i<100;i=i+1)begin style=i%11;fire(i%15+1);for(j=0;j<37;j=j+1)sample;end
 $display("PASS cue onehot cycle equivalence: cycles=%0d samples=%0d legacy/page/invalid/interrupt",cycles,samples);$finish;
end
endmodule
