// Relative TJC touchpad. All state uses the existing 75 MHz pixel clock.
// Only an unmoved short press/release generates a click; lost releases expire.
module photo_touchpad #(
 parameter integer CLK_HZ=75000000,
 parameter integer TAP_MIN_MS=20,TAP_MAX_MS=250,CONTACT_TIMEOUT_MS=180
)(
 input clk,rst,enable,frame_tick,sample_valid,sample_down,
 input [9:0] sample_x,input [8:0] sample_y,
 output reg [10:0] cursor_x,output reg [9:0] cursor_y,
 output reg click,output reg contact
);
localparam integer MS_CLKS=CLK_HZ/1000;
reg [16:0] ms_count;
wire ms_tick=ms_count==MS_CLKS-1;
reg [7:0] age,quiet;
reg moved;
reg [9:0] last_x,origin_x;
reg [8:0] last_y,origin_y;
reg [10:0] pos_x;reg [9:0] pos_y;
wire signed [11:0] dx=$signed({2'b00,sample_x})-$signed({2'b00,last_x});
wire signed [10:0] dy=$signed({2'b00,sample_y})-$signed({2'b00,last_y});
wire signed [12:0] nx=$signed({2'b00,pos_x})+($signed({dx[11],dx})<<<1);
wire signed [11:0] ny=$signed({2'b00,pos_y})+($signed({dy[10],dy})<<<1);
wire signed [10:0] origin_dx=$signed({1'b0,sample_x})-$signed({1'b0,origin_x});
wire signed [9:0] origin_dy=$signed({1'b0,sample_y})-$signed({1'b0,origin_y});
wire far_x=origin_dx>11'sd8 || origin_dx< -11'sd8;
wire far_y=origin_dy>10'sd8 || origin_dy< -10'sd8;
always @(posedge clk or posedge rst)begin
 if(rst)begin
  ms_count<=0;age<=0;quiet<=0;moved<=0;contact<=0;click<=0;
  last_x<=0;last_y<=0;origin_x<=0;origin_y<=0;
  pos_x<=640;pos_y<=360;cursor_x<=640;cursor_y<=360;
 end else begin
  ms_count<=ms_tick ? 0:ms_count+1'b1;click<=0;
  if(frame_tick)begin cursor_x<=pos_x;cursor_y<=pos_y;end
  if(!enable)begin contact<=0;age<=0;quiet<=0;moved<=0;end
  else begin
   if(ms_tick && contact)begin
    if(age!=255)age<=age+1'b1;
    if(quiet>=CONTACT_TIMEOUT_MS-1)begin contact<=0;moved<=1;end
    else quiet<=quiet+1'b1;
   end
   if(sample_valid)begin
    quiet<=0;
    if(sample_down)begin
     last_x<=sample_x;last_y<=sample_y;
     if(!contact)begin
      contact<=1;origin_x<=sample_x;origin_y<=sample_y;age<=0;moved<=0;
     end else begin
      // Gain 2 is a shift, with saturation rather than coordinate wrap.
      pos_x<=nx<0 ? 11'd0:nx>1279 ? 11'd1279:nx[10:0];
      pos_y<=ny<0 ? 10'd0:ny>719 ? 10'd719:ny[9:0];
      if(far_x || far_y)moved<=1;
     end
    end else begin
     contact<=0;
     if(contact && !moved && !far_x && !far_y && age>=TAP_MIN_MS && age<TAP_MAX_MS)
      click<=1;
    end
   end
  end
 end
end
endmodule

// Raster cursor and settings launcher, aligned with the existing 26-clock RGB.
// No RAM, multiplier, extra video latency, or SDRAM traffic.
module photo_pointer_overlay #(parameter DELAY=26,NAVIGATION_BUTTON=1)(
 input clk,rst,frame_tick,enable,de,navigation_enable,input [11:0] x,input [10:0] y,
 input [10:0] cursor_x,input [9:0] cursor_y,
 input [23:0] rgb_in,output [23:0] rgb_out
);
reg visible,navigation_visible;
wire next_button=x>=1192 && x<1256 && y>=328 && y<392;
wire next_ink=(x>=1208 && x<1224 && y>=356 && y<364) ||
 (x>=1224 && x<1232 && y>=344 && y<376) ||
 (x>=1232 && x<1240 && y>=352 && y<368) ||
 (x>=1240 && x<1244 && y>=356 && y<364);
reg [11:0] dx;reg [10:0] dy;reg bounds,button,button_ink;
reg [DELAY-2:0] body_pipe,border_pipe,button_pipe,ink_pipe;
wire body=bounds && dx<16 && dy<24 && {1'b0,dx[3:0]}<=({1'b0,dy[4:1]}+5'd1);
wire border=body && (dx[3:0]<2 || dy[4:0]>21 || {dx[3:0],1'b0}>=dy[4:0]);
always @(posedge clk or posedge rst)begin
 if(rst)begin visible<=0;navigation_visible<=0;dx<=0;dy<=0;bounds<=0;button<=0;button_ink<=0;
  body_pipe<=0;border_pipe<=0;button_pipe<=0;ink_pipe<=0;
 end else begin
  if(frame_tick)begin visible<=enable;navigation_visible<=navigation_enable;end
  dx<=x-{1'b0,cursor_x};dy<=y-{1'b0,cursor_y};
  bounds<=visible && de && x>={1'b0,cursor_x} && y>={1'b0,cursor_y};
  button<=visible && de && ((x>=1152 && x<1256 && y>=24 && y<64) || (NAVIGATION_BUTTON && navigation_visible && next_button));
  // Three horizontal menu lines and a simple frame remain readable at 720p.
  button_ink<=(x>=1180 && x<1228 && ((y>=34 && y<38)||(y>=44 && y<48)||(y>=54 && y<58))) || (NAVIGATION_BUTTON && navigation_visible && next_button && next_ink);
  body_pipe<={body_pipe[DELAY-3:0],body};border_pipe<={border_pipe[DELAY-3:0],border};
  button_pipe<={button_pipe[DELAY-3:0],button};ink_pipe<={ink_pipe[DELAY-3:0],button_ink};
 end
end
assign rgb_out=body_pipe[DELAY-2] ? (border_pipe[DELAY-2] ? 24'h101820:24'hffffff):
 button_pipe[DELAY-2] ? (ink_pipe[DELAY-2] ? 24'hffffff:24'h205f7a):rgb_in;
endmodule
