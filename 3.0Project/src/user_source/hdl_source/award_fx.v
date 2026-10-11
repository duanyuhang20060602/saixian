// Antialiased foil sprites, graded mesh/node glow and wall-lamp breathing.
// Five pipeline stages; delta_video delays DE/VS/boot by the same latency.
module award_fx(
 input clk,input rst,input enable,input pause,input frame_tick,
 input [10:0] x,input [9:0] y,input [23:0] base_rgb,input [5:0] tag,
 output reg [23:0] rgb
);
(* async_reg="true" *) reg pause_meta,pause_sync;
reg [9:0] motion,fraction;reg [6:0] initial_frames;
wire [10:0] next_fraction={1'b0,fraction}+11'd296;
always @(posedge clk)begin
 if(rst || !enable)begin motion<=0;fraction<=0;initial_frames<=0;pause_meta<=0;pause_sync<=0;end
 else begin
  pause_meta<=pause;pause_sync<=pause_meta;
  if(frame_tick && !pause_sync)begin
   if(initial_frames<61)initial_frames<=initial_frames+1'b1;
   else if(next_fraction>=364)begin motion<=motion+10'd3;fraction<=next_fraction-11'd364;end
   else begin motion<=motion+10'd2;fraction<=next_fraction[9:0];end
  end
 end
end
function [15:0] seed_for_column;
 input [4:0] column;
 begin case(column)
 0:seed_for_column=16'h0581;1:seed_for_column=16'h184d;2:seed_for_column=16'h6a39;3:seed_for_column=16'h3318;
 4:seed_for_column=16'h92e5;5:seed_for_column=16'h7c91;6:seed_for_column=16'h492d;7:seed_for_column=16'h257a;
 8:seed_for_column=16'h8571;9:seed_for_column=16'h6574;10:seed_for_column=16'h162b;11:seed_for_column=16'hd941;
 12:seed_for_column=16'h5460;13:seed_for_column=16'h6479;14:seed_for_column=16'h8601;15:seed_for_column=16'h7047;
 16:seed_for_column=16'hac81;17:seed_for_column=16'h2de1;18:seed_for_column=16'h5123;19:seed_for_column=16'hb61a;
 20:seed_for_column=16'h846f;21:seed_for_column=16'h2c41;22:seed_for_column=16'h4e0c;23:seed_for_column=16'hd6a1;
 24:seed_for_column=16'h7800;25:seed_for_column=16'h11fa;26:seed_for_column=16'hc8d3;27:seed_for_column=16'h485c;
 28:seed_for_column=16'h19b1;29:seed_for_column=16'hb309;30:seed_for_column=16'h2fc5;31:seed_for_column=16'h6923;
 32:seed_for_column=16'hb602;33:seed_for_column=16'h7391;34:seed_for_column=16'h1ce0;35:seed_for_column=16'h480d;
 36:seed_for_column=16'h7631;37:seed_for_column=16'h1a39;38:seed_for_column=16'hf6a5;39:seed_for_column=16'hcde1;
 default:seed_for_column=0;
endcase end
endfunction
function [8:0] bend;input [5:0] q;begin case(q)
 6'd0:bend=9'd474;
 6'd1:bend=9'd469;
 6'd2:bend=9'd472;
 6'd3:bend=9'd482;
 6'd4:bend=9'd498;
 6'd5:bend=9'd4;
 6'd6:bend=9'd21;
 6'd7:bend=9'd35;
 6'd8:bend=9'd42;
 6'd9:bend=9'd42;
 6'd10:bend=9'd34;
 6'd11:bend=9'd20;
 6'd12:bend=9'd3;
 6'd13:bend=9'd497;
 6'd14:bend=9'd481;
 6'd15:bend=9'd472;
 6'd16:bend=9'd469;
 6'd17:bend=9'd474;
 6'd18:bend=9'd486;
 6'd19:bend=9'd503;
 6'd20:bend=9'd9;
 6'd21:bend=9'd26;
 6'd22:bend=9'd38;
 6'd23:bend=9'd43;
 6'd24:bend=9'd40;
 6'd25:bend=9'd31;
 6'd26:bend=9'd15;
 6'd27:bend=9'd509;
 6'd28:bend=9'd492;
 6'd29:bend=9'd478;
 6'd30:bend=9'd470;
 6'd31:bend=9'd470;
 6'd32:bend=9'd477;
 6'd33:bend=9'd491;
 6'd34:bend=9'd508;
 6'd35:bend=9'd14;
 6'd36:bend=9'd30;
 6'd37:bend=9'd40;
 6'd38:bend=9'd43;
 6'd39:bend=9'd38;
 default:bend=0;endcase end endfunction
function [6:0] breath;input [5:0] q;begin case(q)
 6'd0:breath=7'd0;
 6'd1:breath=7'd0;
 6'd2:breath=7'd1;
 6'd3:breath=7'd1;
 6'd4:breath=7'd2;
 6'd5:breath=7'd4;
 6'd6:breath=7'd5;
 6'd7:breath=7'd7;
 6'd8:breath=7'd9;
 6'd9:breath=7'd12;
 6'd10:breath=7'd14;
 6'd11:breath=7'd17;
 6'd12:breath=7'd20;
 6'd13:breath=7'd23;
 6'd14:breath=7'd26;
 6'd15:breath=7'd29;
 6'd16:breath=7'd32;
 6'd17:breath=7'd35;
 6'd18:breath=7'd38;
 6'd19:breath=7'd41;
 6'd20:breath=7'd44;
 6'd21:breath=7'd47;
 6'd22:breath=7'd50;
 6'd23:breath=7'd52;
 6'd24:breath=7'd55;
 6'd25:breath=7'd57;
 6'd26:breath=7'd59;
 6'd27:breath=7'd60;
 6'd28:breath=7'd62;
 6'd29:breath=7'd63;
 6'd30:breath=7'd63;
 6'd31:breath=7'd64;
 6'd32:breath=7'd64;
 6'd33:breath=7'd64;
 6'd34:breath=7'd63;
 6'd35:breath=7'd63;
 6'd36:breath=7'd62;
 6'd37:breath=7'd60;
 6'd38:breath=7'd59;
 6'd39:breath=7'd57;
 6'd40:breath=7'd55;
 6'd41:breath=7'd52;
 6'd42:breath=7'd50;
 6'd43:breath=7'd47;
 6'd44:breath=7'd44;
 6'd45:breath=7'd41;
 6'd46:breath=7'd38;
 6'd47:breath=7'd35;
 6'd48:breath=7'd32;
 6'd49:breath=7'd29;
 6'd50:breath=7'd26;
 6'd51:breath=7'd23;
 6'd52:breath=7'd20;
 6'd53:breath=7'd17;
 6'd54:breath=7'd14;
 6'd55:breath=7'd12;
 6'd56:breath=7'd9;
 6'd57:breath=7'd7;
 6'd58:breath=7'd5;
 6'd59:breath=7'd4;
 6'd60:breath=7'd2;
 6'd61:breath=7'd1;
 6'd62:breath=7'd1;
 6'd63:breath=7'd0;
 default:breath=0;endcase end endfunction
function [6:0] wave_curve;input [5:0] q;begin case(q)
 6'd0:wave_curve=7'd64;
 6'd1:wave_curve=7'd63;
 6'd2:wave_curve=7'd60;
 6'd3:wave_curve=7'd56;
 6'd4:wave_curve=7'd50;
 6'd5:wave_curve=7'd44;
 6'd6:wave_curve=7'd37;
 6'd7:wave_curve=7'd31;
 6'd8:wave_curve=7'd24;
 6'd9:wave_curve=7'd19;
 6'd10:wave_curve=7'd14;
 6'd11:wave_curve=7'd10;
 6'd12:wave_curve=7'd7;
 6'd13:wave_curve=7'd5;
 6'd14:wave_curve=7'd3;
 6'd15:wave_curve=7'd2;
 6'd16:wave_curve=7'd1;
 6'd17:wave_curve=7'd1;
 6'd18:wave_curve=7'd0;
 6'd19:wave_curve=7'd0;
 6'd20:wave_curve=7'd0;
 6'd21:wave_curve=7'd0;
 6'd22:wave_curve=7'd0;
 6'd23:wave_curve=7'd0;
 6'd24:wave_curve=7'd0;
 6'd25:wave_curve=7'd0;
 6'd26:wave_curve=7'd0;
 6'd27:wave_curve=7'd0;
 6'd28:wave_curve=7'd0;
 6'd29:wave_curve=7'd0;
 6'd30:wave_curve=7'd0;
 6'd31:wave_curve=7'd0;
 6'd32:wave_curve=7'd0;
 6'd33:wave_curve=7'd0;
 6'd34:wave_curve=7'd0;
 6'd35:wave_curve=7'd0;
 6'd36:wave_curve=7'd0;
 6'd37:wave_curve=7'd0;
 6'd38:wave_curve=7'd0;
 6'd39:wave_curve=7'd0;
 6'd40:wave_curve=7'd0;
 6'd41:wave_curve=7'd0;
 6'd42:wave_curve=7'd0;
 6'd43:wave_curve=7'd0;
 6'd44:wave_curve=7'd0;
 6'd45:wave_curve=7'd0;
 6'd46:wave_curve=7'd0;
 6'd47:wave_curve=7'd0;
 6'd48:wave_curve=7'd0;
 6'd49:wave_curve=7'd0;
 6'd50:wave_curve=7'd0;
 6'd51:wave_curve=7'd0;
 6'd52:wave_curve=7'd0;
 6'd53:wave_curve=7'd0;
 6'd54:wave_curve=7'd0;
 6'd55:wave_curve=7'd0;
 6'd56:wave_curve=7'd0;
 6'd57:wave_curve=7'd0;
 6'd58:wave_curve=7'd0;
 6'd59:wave_curve=7'd0;
 6'd60:wave_curve=7'd0;
 6'd61:wave_curve=7'd0;
 6'd62:wave_curve=7'd0;
 6'd63:wave_curve=7'd0;
 default:wave_curve=0;endcase end endfunction

wire live=enable && initial_frames>=61;
wire [8:0] phase=motion[8:0]+y[8:0]+bend(x[10:5]);
reg [8:0] phase0;reg [10:0] x0;reg [9:0] y0,motion0;
reg [15:0] seed0;reg [23:0] base0;reg [5:0] tag0;reg live0;
wire [8:0] distance=phase0[8] ? (~phase0+9'd1) : phase0;
wire [6:0] wave=wave_curve(distance[8:3]);
// Both effects have a dark phase: the plate highlights must not hide the sweep.
wire signed [7:0] intensity=tag0[5] ? $signed({1'b0,breath(motion0[9:4])})-8'sd32 : $signed({1'b0,wave})-8'sd32;
wire signed [12:0] weighted=$signed({1'b0,tag0[4:1]})*intensity;
wire [15:0] seed=seed_for_column(x[10:6]);
function [10:0] sprite_address;
 input [1:0] layer;input [10:0] px;input [9:0] py,clock_phase;input [15:0] random_seed;
 reg [9:0] center_y;reg [4:0] sway_phase;reg signed [6:0] sway;
 reg [6:0] center_x;reg [10:0] dx,dy;reg [2:0] orientation;
 begin
  case(layer)
   0:center_y=clock_phase+random_seed[9:0];
   1:center_y={clock_phase[8:0],1'b0}+random_seed[9:0]+10'd377;
   2:center_y=clock_phase+random_seed[9:0]+10'd619;
   3:center_y=clock_phase+{clock_phase[8:0],1'b0}+random_seed[9:0]+10'd173;
  endcase
  sway_phase=clock_phase[8:4]+random_seed[4:0]+{3'd0,layer};
  sway=sway_phase[4] ? 7'sd15-$signed({3'd0,sway_phase[3:0]}) : $signed({3'd0,sway_phase[3:0]});
  center_x=7'd16+{2'd0,random_seed[14:10]}+(sway>>>1)-7'd4;
  dx={5'd0,px[5:0]}+11'd8-center_x;dy={1'b0,py}+11'd8-center_y;
  orientation=clock_phase[6:4]+random_seed[15:13]+{layer,1'b0};
  sprite_address=px<1280 && py<548 && dx<16 && dy<16 ? {orientation,dy[3:0],dx[3:0]} : 11'd0;
 end
endfunction
reg [10:0] address0,address1,address2,address3;
reg [23:0] base1,flow2;reg signed [9:0] gain1;
wire [7:0] sprite0,sprite1,sprite2,sprite3;
award_sprite_rom sprites(clk,address0,address1,address2,address3,sprite0,sprite1,sprite2,sprite3);
function [7:0] clamp;
 input signed [11:0] value;
 begin clamp=value<0 ? 8'd0 : value>255 ? 8'd255 : value[7:0];end
endfunction
function [7:0] illuminate;
 input [7:0] channel;input signed [9:0] gain;
 reg signed [18:0] product;
 begin
  product=$signed({1'b0,channel})*gain;
  illuminate=clamp($signed({1'b0,channel})+(product>>>8));
 end
endfunction
wire [23:0] lit={illuminate(base1[23:16],gain1),
 illuminate(base1[15:8],gain1),illuminate(base1[7:0],gain1)};
wire [7:0] selected01=sprite0[7:4]>=sprite1[7:4] ? sprite0 : sprite1;
wire [7:0] selected23=sprite2[7:4]>=sprite3[7:4] ? sprite2 : sprite3;
wire [7:0] selected=selected01[7:4]>=selected23[7:4] ? selected01 : selected23;
reg [7:0] selected3;reg [23:0] flow3;
wire [7:0] foil_r=8'd188+{2'd0,selected3[3:0],2'b0};
wire [7:0] foil_g=8'd122+{1'b0,selected3[3:0],3'b0};
wire [7:0] foil_b=8'd46+{2'd0,selected3[3:0],2'b0};
function [7:0] blend;
 input [7:0] background,foreground;input [3:0] opacity;
 reg signed [8:0] difference;reg signed [13:0] product;
 begin
  difference=$signed({1'b0,foreground})-$signed({1'b0,background});
  product=difference*$signed({1'b0,opacity});
  blend=clamp($signed({1'b0,background})+(product>>>4));
 end
endfunction
always @(posedge clk)begin
 if(rst)begin base0<=0;tag0<=0;live0<=0;phase0<=0;x0<=0;y0<=0;motion0<=0;seed0<=0;selected3<=0;flow3<=0;base1<=0;gain1<=0;flow2<=0;rgb<=0;address0<=0;address1<=0;address2<=0;address3<=0;end
 else begin
  base0<=base_rgb;tag0<=tag;live0<=live;phase0<=phase;x0<=x;y0<=y;motion0<=motion;seed0<=seed;
  base1<=base0;gain1<=live0 && tag0[0] ? weighted>>>2 : 10'sd0;
  address0<=live0 ? sprite_address(0,x0,y0,motion0,seed0) : 0;
  address1<=live0 ? sprite_address(1,x0,y0,motion0,seed0^16'h5429) : 0;
  address2<=live0 ? sprite_address(2,x0,y0,motion0,seed0^16'h9561) : 0;
  address3<=live0 ? sprite_address(3,x0,y0,motion0,seed0^16'h39ac) : 0;
  flow2<=lit;
  flow3<=flow2;selected3<=selected;
  rgb<={blend(flow3[23:16],foil_r,selected3[7:4]),blend(flow3[15:8],foil_g,selected3[7:4]),blend(flow3[7:0],foil_b,selected3[7:4])};
 end
end
endmodule
