// Native four-word SDRAM reads share the existing framebuffer controller.
// The claim spans response and recovery; no client can interleave a burst.
module photo_award_memory(
 input clk,rst,enable,init_done,refresh,busy,frame_busy,
 input request,input [20:0] address,output reg acknowledge,
 output reg [31:0] data,output reg valid,
 output claim,output read_command,output [20:0] read_address,
 input response_valid,input [31:0] response
);
localparam IDLE=0,READ=1,RECOVER=2,WAIT_LOW=3;
reg [1:0] state;reg [2:0] count,issued;reg [3:0] recovery;reg [20:0] latched;
assign claim=state==READ || state==RECOVER;
assign read_command=state==READ && issued<4 && !refresh;
assign read_address=latched+issued;
always @(posedge clk or posedge rst)
 if(rst)begin state<=IDLE;count<=0;issued<=0;recovery<=0;latched<=0;acknowledge<=0;data<=0;valid<=0;end
 else begin
  acknowledge<=0;valid<=0;
  case(state)
   IDLE:if(enable && request && init_done && !refresh && !busy && !frame_busy)begin
    latched<={address[20:2],2'b00};state<=READ;count<=0;issued<=0;recovery<=0;acknowledge<=1;
   end
   READ:begin
    if(read_command)issued<=issued+1'b1;
    if(response_valid)begin data<=response;valid<=1;count<=count+1'b1;
     if(count==3)begin state<=RECOVER;recovery<=0;end
    end
   end
   RECOVER:if(recovery==10)state<=IDLE;else recovery<=recovery+1'b1;
   WAIT_LOW:if(!request)state<=IDLE;
   default:state<=IDLE;
  endcase
 end
endmodule
