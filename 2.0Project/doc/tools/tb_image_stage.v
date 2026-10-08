`timescale 1ns/1ps
// Research-only: exercise the actual image enhancer on a complete image.
// Inputs are RGB565 expanded to RGB888, as after the framebuffer read.
module tb_image_stage #(parameter PHOTO_SMOOTH=0, FIXED_GAIN=-1);
reg clk=0,rst=1,de=0,vs=0,ft=0;always #5 clk=~clk;
reg [10:0] x=0;reg [9:0] y=0;reg [23:0] rgb=0;
reg [23:0] source[0:921599];
wire [23:0] bypass,enhanced;wire valid_b,valid_e;wire [1:0] gain;
saixian_adaptive_enhance bypass_stage(.clk(clk),.rst(rst),.de(de),.vs(vs),.frame_tick(ft),.statistics_enable(1'b1),
 .x(x),.y(y),.rgb_in(rgb),.mode(2'd0),.strength(2'd0),.rgb_out(bypass),.de_out(valid_b));
saixian_adaptive_enhance #(.PHOTO_SMOOTH(PHOTO_SMOOTH)) enhanced_stage(.clk(clk),.rst(rst),.de(de),.vs(vs),.frame_tick(ft),.statistics_enable(1'b1),
 .x(x),.y(y),.rgb_in(rgb),.mode(2'd1),.strength(2'd1),.rgb_out(enhanced),.de_out(valid_e),.gain_out(gain));
reg [1023:0] input_path,output_path;integer file,k,row,col,count=0;
always @(posedge clk)begin
 #1;
 if(!rst && valid_b)begin
  if(!valid_e || bypass!==source[count])$fatal(1,"bypass/alignment mismatch %0d",count);
  $fwrite(file,"%h,%h\n",bypass,enhanced);count=count+1;
 end
end
initial begin
 if(!$value$plusargs("IN=%s",input_path) || !$value$plusargs("OUT=%s",output_path))$fatal(1,"Paths required");
 $readmemh(input_path,source);file=$fopen(output_path,"w");
 if(!file)$fatal(1,"Trace open failed");
 repeat(4)@(negedge clk);rst=0;
 // Research only: isolate spatial filtering from adaptive tone lift.
 if(FIXED_GAIN>=0) enhanced_stage.gain=FIXED_GAIN;
 for(row=0;row<720;row=row+1)begin
  for(col=0;col<1280;col=col+1)begin
   @(negedge clk);de=1;x=col;y=row;rgb=source[row*1280+col];
  end
  @(negedge clk);de=0;repeat(8)@(negedge clk);
 end
 repeat(20)@(negedge clk);$fclose(file);
 if(count!=921600)$fatal(1,"Incomplete frame %0d",count);
 $display("PASS actual enhancer: 921600 aligned RGB565 pixels, exact bypass, full-frame processing (gain=%0d)",gain);$finish;
end
initial begin #20000000;$fatal(1,"Image-stage timeout");end
endmodule
