module water_scene(input clk,rst,frame_tick,display_valid,transition_active,
 input wave_enable,manual_drop,input[8:0] progress,output[76:0] cfg);
reg[8:0] dwell;reg[7:0] age0,age1;reg[23:0] radius0,radius1;
reg[10:0] cx0,cx1;reg[9:0] cy0,cy1;reg[15:0] step0,step1;reg[2:0] sequence;
reg transition_d,pending_manual;
function[36:0] point;input[2:0] n;begin case(n)
0:point={11'd998,10'd454,16'd3604};1:point={11'd346,10'd432,16'd3400};
2:point={11'd717,10'd547,16'd3020};3:point={11'd1062,10'd497,16'd3832};
4:point={11'd346,10'd511,16'd3508};5:point={11'd986,10'd425,16'd3534};
6:point={11'd346,10'd475,16'd3454};default:point={11'd986,10'd504,16'd3636};endcase end endfunction
wire on0=wave_enable&&age0<85&&!transition_active;
wire on1=wave_enable&&age1<85&&!transition_active;
assign cfg={on0,on1,cx0,cx1,cy0,cy1,radius0[19:8],radius1[19:8],progress};
always @(posedge clk)begin
 if(rst)begin dwell<=0;age0<=255;age1<=255;radius0<=0;radius1<=0;cx0<=0;cx1<=0;cy0<=0;cy1<=0;step0<=0;step1<=0;sequence<=0;transition_d<=0;pending_manual<=0;end
 else begin
  if(manual_drop)pending_manual<=1;
  if(frame_tick)begin
   transition_d<=transition_active;
   if(!display_valid||transition_active||!wave_enable)begin
    dwell<=0;age0<=255;age1<=255;radius0<=0;radius1<=0;
    if(transition_active&&!transition_d)sequence<=sequence+1'b1;
   end else begin
    if(dwell<300)dwell<=dwell+1'b1;
    if(age0<85)begin age0<=age0+1'b1;radius0<=radius0+step0;end
    if(age1<85)begin age1<=age1+1'b1;radius1<=radius1+step1;end
    if(dwell==45||pending_manual)begin
     {cx0,cy0,step0}<=point(sequence);age0<=0;radius0<=0;pending_manual<=0;
    end
    if(dwell==57&&sequence[0])begin {cx1,cy1,step1}<=point(sequence+1'b1);age1<=0;radius1<=0;end
   end
  end
 end
end
endmodule
