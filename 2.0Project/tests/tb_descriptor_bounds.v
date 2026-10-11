`timescale 1ns/1ps
module tb_descriptor_bounds;
reg clk=0,rst=1;
reg [31:0] offset,words,duration;
reg [20:0] file_words;
wire ss,bs;
wire [4:0] state,bstate;
wire [3:0] error,berror;
reg [31:0] command,bcommand;
integer i;
always #5 clk=~clk;
delta_player #(.VERIFY_STREAM(1)) dut(.clk(clk),.rst(rst),.cache_ready(1'b1),.file_words(file_words),.frame_count(6'd1),
 .stream_start(ss),.stream_ack(ss),.cmd_data(command),.cmd_valid(state==2),.state(state),.error(error),.pause(1'b0),.patch_ready(1'b0));
baseline_delta_player #(.VERIFY_STREAM(1)) baseline(.clk(clk),.rst(rst),.cache_ready(1'b1),.file_words(file_words),.frame_count(6'd1),
 .stream_start(bs),.stream_ack(bs),.cmd_data(bcommand),.cmd_valid(bstate==2),.state(bstate),.error(berror),.pause(1'b0),.patch_ready(1'b0));
always @*begin
 case(dut.index_word) 0:command=offset;1:command=words;2:command=duration;default:command=0;endcase
 case(baseline.index_word) 0:bcommand=offset;1:bcommand=words;2:bcommand=duration;default:bcommand=0;endcase
end
initial begin
for(i=0;i<1000;i=i+1)begin
 rst=1;repeat(3)@(negedge clk);
 file_words=21'h1fffff;offset=384;words=2;duration=1000000;
 case(i)
  0: ;
  1:offset=32'h00200180;
  2:words=32'h00200002;
  3:begin offset=21'h1e0000;words=21'h1e0000;end
  4:offset=0;
  5:words=0;
  6:duration=0;
  7:duration=500000001;
  8:offset=32'h80000180;
  9:words=32'h80000002;
  default:begin offset=$random;words=$random;duration=$random;end
 endcase
 rst=0;repeat(30)@(negedge clk);
 if(error!==berror || state!==bstate)$fatal(1,"descriptor range differs at %d error=%d/%d state=%d/%d",i,error,berror,state,bstate);
 if(i==0 && error!==0)$fatal(1,"valid descriptor rejected");
 if(i==1 && error!==11)$fatal(1,"offset high bits lost");
 if(i==2 && error!==12)$fatal(1,"length high bits lost");
 if(i==3 && error!==13)$fatal(1,"address sum wrapped");
end
$display("PASS descriptor width: exact original acceptance/error timing for valid, high-bit, overflow, duration and random descriptors");$finish;
end
endmodule
