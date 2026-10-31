module production_gain(input clk,rst,loading,scaler_pixel,load_start,input [10:0] stat_x,input [9:0] stat_y,input [12:0] stat_count,input [20:0] stat_sum,output [1:0] result,reference);
wire [20:0] count_ext={8'd0,stat_count};
reg [14:0] stat_count3;
reg [16:0] stat_count9;
wire stat_sample=loading && scaler_pixel && stat_x[3:0]==0 && stat_y[3:0]==0;
always @(posedge clk or posedge rst)begin:gain_counts
 if(rst)begin stat_count3<=0;stat_count9<=0;end
 else if(stat_sample)begin
  stat_count3<=stat_count==13'h1fff ? 15'd0:stat_count3+15'd3;
  stat_count9<=stat_count==13'h1fff ? 17'd0:stat_count9+17'd9;
 end else if(load_start)begin stat_count3<=0;stat_count9<=0;end
end
wire [1:0] loaded_gain=stat_sum<(count_ext<<6) ? 2'd3:
 stat_sum<{1'b0,stat_count3,5'd0} ? 2'd2:
 stat_sum<{stat_count9,4'd0} ? 2'd1:2'd0;
wire [1:0] original_gain=stat_sum<(count_ext<<6) ? 2'd3:
 stat_sum<((count_ext<<6)+(count_ext<<5)) ? 2'd2:
 stat_sum<((count_ext<<7)+(count_ext<<4)) ? 2'd1:2'd0;
assign result=loaded_gain;assign reference=original_gain;endmodule
