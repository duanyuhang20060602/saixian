// A-board startup UI; no SD asset, SDRAM read or board-B dependency to draw.
// One-shot exit occurs in vertical blanking after a real frame is available.
module photo_boot_screen #(parameter VIDEO_DELAY=26,MIN_FRAMES=90,STAGED_LOADING=0)(
 input clk,rst,frame_tick,input [11:0] x,input [10:0] y,
 input memory_ready,catalog_ready,frame_ready,animation_ready,audio_ready,
 output reg active,output [23:0] rgb);
reg [7:0] elapsed,phase;reg [8:0] progress;reg [2:0] stable;
// Four completed milestones: 25% initialization, 50% animation,
// 75% first valid display frame, 100% playable audio (or confirmed no music).
wire all_ready=frame_ready && (!STAGED_LOADING || (memory_ready && catalog_ready && animation_ready && audio_ready));
wire [8:0] target=STAGED_LOADING ?
 (!memory_ready || !animation_ready ? 9'd120:!catalog_ready || !frame_ready ? 9'd240:!audio_ready ? 9'd360:9'd480):
 (frame_ready ? 9'd480:catalog_ready ? 9'd400:memory_ready ? 9'd224:9'd80);
// Decode the slowly changing loading milestone before the glyph/color path.
// This one-clock metadata register updates during vertical blanking; the
// coordinate/RGB pipeline keeps exactly VIDEO_DELAY cycles.
reg [2:0] loading_stage;
always @(posedge clk or posedge rst)
 if(rst)loading_stage<=0;
 else loading_stage<=!memory_ready ? 0:progress<240 ? 1:progress<360 ? 2:progress<480 ? 3:4;
always @(posedge clk or posedge rst)begin
 if(rst)begin active<=1;elapsed<=0;phase<=0;progress<=STAGED_LOADING ? 9'd120:9'd0;stable<=0;end
 else if(frame_tick && active)begin
  phase<=phase+1'b1;
  if(elapsed<MIN_FRAMES)elapsed<=elapsed+1'b1;
  if(progress<target)progress<=target-progress<8 ? target:progress+9'd8;
  if(all_ready)begin if(stable<4)stable<=stable+1'b1;end else stable<=0;
  if(elapsed>=MIN_FRAMES && stable>=3 && all_ready && progress==480)active<=0;
 end
end

reg [23:0] color;reg [2:0] dot;reg on_dot;
reg [7:0] ch;reg [34:0] glyph;reg ink;
wire [11:0] tx=x-(STAGED_LOADING ? 12'd600:12'd584);wire [10:0] ty=y-11'd328;
wire text_box=x>=(STAGED_LOADING ? 600:584) && x<(STAGED_LOADING ? 680:696) && y>=328 && y<342;
wire [8:0] bar_x=x-12'd400;
wire [2:0] age=phase[4:2]-dot;
always @*begin
 dot=0;on_dot=0;
 if(x>=635 && x<645 && y>=260 && y<270)begin dot=0;on_dot=1;end
 if(x>=654 && x<664 && y>=268 && y<278)begin dot=1;on_dot=1;end
 if(x>=662 && x<672 && y>=287 && y<297)begin dot=2;on_dot=1;end
 if(x>=654 && x<664 && y>=306 && y<316)begin dot=3;on_dot=1;end
 if(x>=635 && x<645 && y>=314 && y<324)begin dot=4;on_dot=1;end
 if(x>=616 && x<626 && y>=306 && y<316)begin dot=5;on_dot=1;end
 if(x>=608 && x<618 && y>=287 && y<297)begin dot=6;on_dot=1;end
 if(x>=616 && x<626 && y>=268 && y<278)begin dot=7;on_dot=1;end
 if(STAGED_LOADING)begin
  ch=" ";
  case(loading_stage)
   0:case(tx[6:4])0:ch="I";1:ch="N";2:ch="I";3:ch="T";endcase
   1:case(tx[6:4])0:ch="A";1:ch="N";2:ch="I";3:ch="M";endcase
   2:case(tx[6:4])0:ch="P";1:ch="H";2:ch="O";3:ch="T";4:ch="O";endcase
   3:case(tx[6:4])0:ch="M";1:ch="U";2:ch="S";3:ch="I";4:ch="C";endcase
   default:case(tx[6:4])0:ch="R";1:ch="E";2:ch="A";3:ch="D";4:ch="Y";endcase
  endcase
 end else case(tx[6:4])
  0:ch="L";1:ch="O";2:ch="A";3:ch="D";4:ch="I";5:ch="N";default:ch="G";
 endcase
 case(ch)
  "L":glyph=35'b10000_10000_10000_10000_10000_10000_11111;
  "O":glyph=35'b01110_10001_10001_10001_10001_10001_01110;
  "A":glyph=35'b01110_10001_10001_11111_10001_10001_10001;
  "D":glyph=35'b11110_10001_10001_10001_10001_10001_11110;
  "I":glyph=35'b11111_00100_00100_00100_00100_00100_11111;
  "N":glyph=35'b10001_11001_11001_10101_10011_10011_10001;
  "M":glyph=35'b10001_11011_10101_10101_10001_10001_10001;
  "P":glyph=35'b11110_10001_10001_11110_10000_10000_10000;
  "H":glyph=35'b10001_10001_10001_11111_10001_10001_10001;
  "T":glyph=35'b11111_00100_00100_00100_00100_00100_00100;
  "U":glyph=35'b10001_10001_10001_10001_10001_10001_01110;
  "S":glyph=35'b01111_10000_10000_01110_00001_00001_11110;
  "C":glyph=35'b01111_10000_10000_10000_10000_10000_01111;
  "R":glyph=35'b11110_10001_10001_11110_10100_10010_10001;
  "E":glyph=35'b11111_10000_10000_11110_10000_10000_11111;
  "Y":glyph=35'b10001_10001_01010_00100_00100_00100_00100;
  " ":glyph=35'd0;
  default:glyph=35'b01110_10001_10000_10111_10001_10001_01110;
 endcase
 ink=text_box && tx[3:1]<5 && glyph[34-(ty[3:1]*5+tx[3:1])];
 color=24'h000000;
 if(on_dot)case(age)
  0:color=24'hb8edff;1:color=24'h7cd8ff;2:color=24'h47baff;
  3:color=24'h2693d1;4:color=24'h17628b;default:color=24'h102c40;
 endcase
 if(ink)color=24'hd0e4ee;
 if(x>=398 && x<882 && y>=372 && y<388)color=24'h163044;
 if(x>=400 && x<880 && y>=374 && y<386)begin
  color=bar_x<progress ? 24'h359cd0:24'h080e14;
  if(STAGED_LOADING && (bar_x==120 || bar_x==240 || bar_x==360))color=24'hd0e4ee;
  if(bar_x<progress && bar_x[5:0]==phase[5:0])color=24'hb8edff;
 end
end
reg [23:0] pixels[0:VIDEO_DELAY-1];integer i;
always @(posedge clk)begin
 if(rst)begin for(i=0;i<VIDEO_DELAY;i=i+1)pixels[i]<=0;end
 else begin pixels[0]<=color;for(i=1;i<VIDEO_DELAY;i=i+1)pixels[i]<=pixels[i-1];end
end
assign rgb=pixels[VIDEO_DELAY-1];
endmodule
