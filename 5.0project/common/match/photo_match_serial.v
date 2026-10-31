// Reuse bytes from the existing HMI receiver: !M:1 CR LF, !A:123 CR LF.
// No second UART, no new pins; legacy binary HMI and @0/@1 text remain intact.
module photo_match_serial #(parameter HZ=75000000,SHARED_TIMEOUT=0)(input clk,rst,
 input byte_valid,input[7:0] byte_data,input can_start,input shared_timeout,
 output busy,output reg valid,output reg[3:0] operation,output reg[9:0] value,output reg error);
localparam TIMEOUT=HZ/20>0 ? HZ/20:1,TW=TIMEOUT>1 ? $clog2(TIMEOUT):1;
reg[2:0] state;
reg[1:0] digits;
reg[TW-1:0] idle;
wire[13:0] next_number=({4'd0,value}<<3)+({4'd0,value}<<1)+{10'd0,byte_data[3:0]};
wire bounds=operation==0 ? value<=1:operation==1 ? value<=7:
 operation==2 || operation==3 ? value<=5:operation==6 ? value<=3:value<=999;
assign busy=state!=0;
always @(posedge clk or posedge rst)
 if(rst)begin state<=0;digits<=0;idle<=0;valid<=0;operation<=0;value<=0;error<=0;end
 else begin
  valid<=0;error<=0;
  if(SHARED_TIMEOUT)begin if(shared_timeout && state!=0)begin state<=0;error<=1;end end
  else if(state==0 || byte_valid)idle<=0;
  else if(idle==TIMEOUT-1)begin idle<=0;state<=0;error<=1;end else idle<=idle+1'b1;
  if(byte_valid)begin
   if(byte_data=="!" && can_start)begin state<=1;digits<=0;value<=0;end
   else case(state)
    0:begin end
    1:begin
     state<=2;
     case(byte_data)
      "M":operation<=0;"K":operation<=1;"H":operation<=2;"V":operation<=3;
      "A":operation<=4;"B":operation<=5;"T":operation<=6;
      default:begin state<=0;error<=1;end
     endcase
    end
    2:if(byte_data==":")state<=3;else begin state<=0;error<=1;end
    3:if(byte_data>="0" && byte_data<="9" && digits<3 && next_number<=999)begin
      value<=next_number[9:0];digits<=digits+1'b1;
     end else if(byte_data==13 && digits!=0)state<=4;
     else begin state<=0;error<=1;end
    4:begin state<=0;if(byte_data==10 && bounds)valid<=1;else error<=1;end
    default:state<=0;
   endcase
  end
 end
endmodule
