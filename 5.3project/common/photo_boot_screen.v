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
wire [2:0] loading_stage=!memory_ready ? 0:progress<240 ? 1:progress<360 ? 2:progress<480 ? 3:4;
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

reg [3:0] color;reg [2:0] dot;reg on_dot;
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
 color=4'd0;
 if(on_dot)case(age)
  0:color=4'd1;1:color=4'd2;2:color=4'd3;
  3:color=4'd4;4:color=4'd5;default:color=4'd6;
 endcase
 if(ink)color=4'd7;
 if(x>=398 && x<882 && y>=372 && y<388)color=4'd8;
 if(x>=400 && x<880 && y>=374 && y<386)begin
  color=bar_x<progress ? 4'd9:4'd10;
  if(STAGED_LOADING && (bar_x==120 || bar_x==240 || bar_x==360))color=4'd7;
  if(bar_x<progress && bar_x[5:0]==phase[5:0])color=4'd1;
 end
end
function [7:0] pipeline_character;input[2:0] stage,index;reg[7:0] ch;begin
 if(STAGED_LOADING)begin
  ch=" ";
  case(stage)
   0:case(index)0:ch="I";1:ch="N";2:ch="I";3:ch="T";endcase
   1:case(index)0:ch="A";1:ch="N";2:ch="I";3:ch="M";endcase
   2:case(index)0:ch="P";1:ch="H";2:ch="O";3:ch="T";4:ch="O";endcase
   3:case(index)0:ch="M";1:ch="U";2:ch="S";3:ch="I";4:ch="C";endcase
   default:case(index)0:ch="R";1:ch="E";2:ch="A";3:ch="D";4:ch="Y";endcase
  endcase
 end else case(index)
  0:ch="L";1:ch="O";2:ch="A";3:ch="D";4:ch="I";5:ch="N";default:ch="G";
 endcase
 pipeline_character=ch;
end endfunction
function [34:0] pipeline_glyph;input[7:0] ch;reg[34:0] glyph;begin
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
 pipeline_glyph=glyph;
end endfunction

// Four registered rendering stages split stage selection, character lookup,
// glyph lookup and bit selection. Subtract these stages from the colour delay
// so the RGB output remains on the original VIDEO_DELAY edge.
localparam PIPE_DELAY=VIDEO_DELAY>=5 ? VIDEO_DELAY-4:VIDEO_DELAY;
wire[3:0] output_color;
generate if(VIDEO_DELAY>=5)begin:render_pipeline
 reg[2:0] stage0,index0,phase0,dot0;
 reg[5:0] position0,position1,position2;
 reg[6:0] flags0,flags1,flags2,flags3;
 reg[2:0] age1,age2,age3;
 reg[7:0] character1;reg[34:0] glyph2;reg ink3;
 always @(posedge clk)begin
  if(rst)begin
   stage0<=0;index0<=0;phase0<=0;dot0<=0;position0<=0;position1<=0;position2<=0;
   flags0<=0;flags1<=0;flags2<=0;flags3<=0;age1<=0;age2<=0;age3<=0;
   character1<=32;glyph2<=0;ink3<=0;
  end else begin
   stage0<=loading_stage;index0<=tx[6:4];phase0<=phase[4:2];dot0<=dot;
   position0<=ty[3:1]*6'd5+{3'd0,tx[3:1]};
   flags0<={bar_x<progress && bar_x[5:0]==phase[5:0],
    STAGED_LOADING && (bar_x==120 || bar_x==240 || bar_x==360),bar_x<progress,
    x>=400 && x<880 && y>=374 && y<386,
    x>=398 && x<882 && y>=372 && y<388,text_box && tx[3:1]<5,on_dot};
   character1<=pipeline_character(stage0,index0);position1<=position0;flags1<=flags0;age1<=phase0-dot0;
   glyph2<=pipeline_glyph(character1);position2<=position1;flags2<=flags1;age2<=age1;
   ink3<=flags2[1] && glyph2[34-position2];flags3<=flags2;age3<=age2;
  end
 end
 reg[3:0] rendered;
 always @*begin
  rendered=0;
  if(flags3[0])case(age3)
   0:rendered=1;1:rendered=2;2:rendered=3;3:rendered=4;4:rendered=5;default:rendered=6;
  endcase
  if(ink3)rendered=7;
  if(flags3[2])rendered=8;
  if(flags3[3])begin
   rendered=flags3[4] ? 9:10;
   if(flags3[5])rendered=7;
   if(flags3[6])rendered=1;
  end
 end
 assign output_color=rendered;
end else begin:short_render
 assign output_color=color;
end endgenerate
// The startup image uses only eleven exact colours. Carry their indices
// through the video delay, then register the decoded RGB on the final edge.
// This keeps every pixel/latency while releasing hundreds of slice registers.
function [23:0] palette;input [3:0] code;begin case(code)
 0:palette=24'h000000;
 1:palette=24'hb8edff;
 2:palette=24'h7cd8ff;
 3:palette=24'h47baff;
 4:palette=24'h2693d1;
 5:palette=24'h17628b;
 6:palette=24'h102c40;
 7:palette=24'hd0e4ee;
 8:palette=24'h163044;
 9:palette=24'h359cd0;
 10:palette=24'h080e14;
 default:palette=24'h000000;
endcase end endfunction
generate if(PIPE_DELAY==1)begin:one_stage
 reg[23:0] value;
 always @(posedge clk)if(rst)value<=0;else value<=palette(output_color);
 assign rgb=value;
end else begin:delayed_palette
 reg[3:0] indices[0:PIPE_DELAY-2];reg[23:0] value;integer i;
 always @(posedge clk)begin
  if(rst)begin for(i=0;i<PIPE_DELAY-1;i=i+1)indices[i]<=0;value<=0;end
  else begin
   indices[0]<=output_color;
   for(i=1;i<PIPE_DELAY-1;i=i+1)indices[i]<=indices[i-1];
   value<=palette(indices[PIPE_DELAY-2]);
  end
 end
 assign rgb=value;
end endgenerate
endmodule
