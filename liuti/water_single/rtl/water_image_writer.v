// Two independently queued image planes. Every grant writes 64 aligned words;
// both row widths (640 and 320) divide into whole grants, including vertical flip.
module water_image_writer #(parameter HEIGHT=720)(
 input clk,rst,initialized,refresh,sdr_busy,reader_busy,request,input[20:0] base,
 input[8:0] full_used,small_used,output reg ack,output finish,output clear,
 output busy,write_en,small_select,output reg[20:0] address);
localparam IDLE=0,ACK=1,WAIT=2,CLAIM=3,WRITE=4,DRAIN=5,FINISH=6;
reg[2:0] state;reg q0,q1,q2;reg[20:0] b0,b1,bq;
reg selected;reg[5:0] count;reg[9:0] fx,sx,fy,sy;
reg[20:0] full_count,small_count;reg[3:0] drain;
wire fready=full_count<HEIGHT*640&&full_used>=64;
wire sready=small_count<HEIGHT*320&&small_used>=64;
assign busy=state==CLAIM||state==WRITE||state==DRAIN;
assign write_en=state==WRITE;assign small_select=selected;
assign finish=state==FINISH;assign clear=state==ACK;
function[20:0] row640;input[9:0] y;begin row640=({11'd0,y}<<9)+({11'd0,y}<<7);end endfunction
function[20:0] row320;input[9:0] y;begin row320=({11'd0,y}<<8)+({11'd0,y}<<6);end endfunction
always @(posedge clk)begin
 if(rst)begin q0<=0;q1<=0;q2<=0;b0<=0;b1<=0;end
 else begin q0<=request;q1<=q0;q2<=q1;b0<=base;b1<=b0;end
end
always @(posedge clk)begin
 if(rst)begin state<=IDLE;ack<=0;bq<=0;selected<=0;count<=0;fx<=0;sx<=0;fy<=0;sy<=0;full_count<=0;small_count<=0;address<=0;drain<=0;end
 else case(state)
  IDLE:if(q2&&initialized)state<=ACK;
  ACK:begin
   ack<=1;bq<=b1;fx<=0;sx<=0;fy<=HEIGHT-1;sy<=HEIGHT-1;full_count<=0;small_count<=0;
   if(!q2)begin ack<=0;state<=WAIT;end
  end
  WAIT:begin
   if(q2)state<=ACK;
   else if(full_count==HEIGHT*640&&small_count==HEIGHT*320)state<=FINISH;
   else if(fready||sready)begin
    // Native plane has twice the incoming rate. Occupancy decides ties.
    selected<=sready&&(!fready||small_used>full_used);state<=CLAIM;
   end
  end
  CLAIM:if(!reader_busy&&!sdr_busy&&!refresh)begin
   address<=selected ? bq+HEIGHT*640+row320(sy)+sx:bq+row640(fy)+fx;
   count<=0;state<=WRITE;
  end
  WRITE:begin
   address<=address+1'b1;count<=count+1'b1;
   if(selected)small_count<=small_count+1'b1;else full_count<=full_count+1'b1;
   if(count==63)begin
    if(selected)begin if(sx==256)begin sx<=0;sy<=sy-1'b1;end else sx<=sx+64;end
    else begin if(fx==576)begin fx<=0;fy<=fy-1'b1;end else fx<=fx+64;end
    drain<=0;state<=DRAIN;
   end
  end
  // Preserve the SDRAM controller's write-to-read turnaround.
  DRAIN:if(drain==15)state<=WAIT;else drain<=drain+1'b1;
  FINISH:state<=IDLE;
  default:state<=IDLE;
 endcase
end
endmodule
