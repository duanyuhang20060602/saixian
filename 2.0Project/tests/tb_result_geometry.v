`timescale 1ns/1ps
module tb_result_geometry;
reg clk=0;always #5 clk=~clk;
reg rst=1,ft=0;
reg [8:0] frame_value=0;
reg [10:0] pixel_x=0;
reg [11:0] dx=0;reg [9:0] dy=0;
saixian_battle_result_fx dut(.clk(clk),.rst(rst),.frame_tick(ft),.trigger(1'b0),
 .select_blue(1'b0),.select_red(1'b0),.select_sprint(1'b0),.x_in(11'd0),.y_in(10'd0),
 .de_in(1'b0),.vs_in(1'b0),.rgb_in(24'd0),.sprint_background_valid(1'b1));
function integer shift_ref;
 input integer f,onset;
 integer age;
 begin
 age=f-onset;
 if(f<onset) shift_ref=160;
 else if(age<8) shift_ref=160-age*16;
 else if(age<16) shift_ref=32-(age-8)*4;
 else shift_ref=0;
 end
endfunction
integer f,x,a,b;
initial begin
 repeat(3) @(negedge clk);rst=0;
 force dut.state=3'd1;
 force dut.next_frame=frame_value;
 force dut.raster_x=pixel_x;
 for(f=0;f<512;f=f+1) begin
  @(negedge clk);frame_value=f;ft=1;
  @(negedge clk);ft=0;
  for(x=0;x<2048;x=x+1) begin
   pixel_x=x;#1;
   if($signed(dut.source_u_a)!==x-448+shift_ref(f,90) ||
      $signed(dut.source_u_b)!==x-448-shift_ref(f,98) ||
      $signed(dut.source_u_c)!==x-448+shift_ref(f,106))
    $fatal(1,"frame-origin equivalence f=%0d x=%0d",f,x);
  end
 end
 force dut.medal_area=1'b1;
 force dut.medal_dx=dx;force dut.medal_dy=dy;
 for(a=0;a<4096;a=a+1) for(b=0;b<1024;b=b+1) begin
  dx=a;dy=b;#1;
  if(dut.medal_outer!==((a<=31)&&(b<=31)&&(a+b<=44)) ||
     dut.medal_inner!==((a<=24)&&(b<=24)&&(a+b<=34)) ||
     dut.medal_star!==((a<=24)&&(b<=24)&&(a+b<=13)))
   $fatal(1,"bounded medal sum mismatch dx=%0d dy=%0d",a,b);
 end
 $display("PASS title origins: 512 frames x 2048 columns; medal geometry: 4194304 cases");
 $finish;
end
endmodule
