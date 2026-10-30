// Every ten seconds transmit a bounded ASCII diagnostic frame. Application
// responses are queued during that frame and emitted without dropping bytes.
module demo_uart_test #(parameter HZ=75000000,PERIOD=HZ*10)(
 input clk,rst,busy,input reply,input[7:0] response,
 input[15:0] rx_count,input[7:0] rx_last,input ready,fault,input[2:0] init_stage,
 output reg send,output reg[7:0] data);
reg[29:0] timer;reg due,active;reg[4:0] index;
reg[15:0] snapshot_count;reg[7:0] snapshot_last,snapshot_status;
reg[7:0] queue[0:63];reg[5:0] wp,rp;reg[6:0] used;
wire take=!busy && !send && !active && used!=0;
wire put=reply && (used<64 || take);
function[7:0] hex;input[3:0] n;begin hex=n<10?8'd48+n:8'd65+n-10;end endfunction
function[7:0] heartbeat_byte;input[4:0] n;begin case(n)
0:heartbeat_byte="U";1:heartbeat_byte="A";2:heartbeat_byte="R";3:heartbeat_byte="T";
4:heartbeat_byte=" ";5:heartbeat_byte="R";6:heartbeat_byte="X";7:heartbeat_byte="=";
8:heartbeat_byte=hex(snapshot_count[15:12]);9:heartbeat_byte=hex(snapshot_count[11:8]);
10:heartbeat_byte=hex(snapshot_count[7:4]);11:heartbeat_byte=hex(snapshot_count[3:0]);
12:heartbeat_byte=" ";13:heartbeat_byte="L";14:heartbeat_byte="A";15:heartbeat_byte="S";16:heartbeat_byte="T";17:heartbeat_byte="=";
18:heartbeat_byte=hex(snapshot_last[7:4]);19:heartbeat_byte=hex(snapshot_last[3:0]);
20:heartbeat_byte=" ";21:heartbeat_byte="S";22:heartbeat_byte="D";23:heartbeat_byte="=";
24:heartbeat_byte=snapshot_status;25:heartbeat_byte=13;default:heartbeat_byte=10;
endcase end endfunction
always @(posedge clk)begin
 if(rst)begin timer<=0;due<=0;active<=0;index<=0;send<=0;data<=0;wp<=0;rp<=0;used<=0;snapshot_count<=0;snapshot_last<=0;snapshot_status<=0;end
 else begin
 send<=0;
 if(timer==PERIOD-1)begin timer<=0;due<=1;end else timer<=timer+1'b1;
 if(put)begin queue[wp]<=response;wp<=wp+1'b1;end
 case({put,take})2'b10:used<=used+1'b1;2'b01:used<=used-1'b1;default:;endcase
 if(!busy && !send)begin
 if(active)begin data<=heartbeat_byte(index);send<=1;if(index==26)begin active<=0;index<=0;end else index<=index+1'b1;end
 else if(used!=0)begin data<=queue[rp];send<=1;rp<=rp+1'b1;end
 else if(due && !reply)begin
 active<=1;due<=0;index<=0;snapshot_count<=rx_count;snapshot_last<=rx_last;
 snapshot_status<=ready?"R":fault?"E":8'd48+init_stage;
 end end
 end end
endmodule
