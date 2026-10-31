// Same RAM depth and data contract as the original FIFO; exact predictive flags.
module photo_match_audio_fifo #(parameter DEPTH=8192,AW=13,RAM32_HEAD=0)(
 input clk,rst,input write_en,input [31:0] write_data,input read_en,
 output [31:0] data,output empty,full,output reg [AW:0] used,
 output reg ge511,ge512,lehalf
);
reg [AW-1:0] wp,rp;
wire push=write_en && !full,pop=read_en && !empty;
// Predict boundary flags for the count after this edge. They equal the
// original live comparisons on every cycle, including reset and simultaneous
// push/pop, and remove the long count-comparator/write/count feedback path.
(* keep="true" *)reg empty_q,full_q;
assign empty=empty_q;assign full=full_q;
always @(posedge clk or posedge rst)
 if(rst)begin empty_q<=1;full_q<=0;ge511<=0;ge512<=0;lehalf<=1;end
 else begin
  empty_q<=(used==0 && !push) || (used==1 && pop && !push);
  full_q<=(used==DEPTH && !pop) || (used==DEPTH-1 && push && !pop);
  if(push && !pop)begin
   if(used==510)ge511<=1;
   if(used==511)ge512<=1;
   if(used==(1<<(AW-1)))lehalf<=0;
  end else if(pop && !push)begin
   if(used==511)ge511<=0;
   if(used==512)ge512<=0;
   if(used==(1<<(AW-1))+1)lehalf<=1;
  end
 end
generate if(RAM32_HEAD==0)begin: inferred
 reg [31:0] memory[0:DEPTH-1]; /* fehdl force_ram=1, ram_style="bram" */
 reg [31:0] q;
 always @(posedge clk)begin if(push)memory[wp]<=write_data;if(pop)q<=memory[rp];end
 assign data=q;
end else if(RAM32_HEAD==DEPTH)begin: all_ram32
 photo_audio_word_ram #(.ADDR(AW),.IMPLEMENT("32K")) memory(
 .clk(clk),.we(push),.wa(wp),.wd(write_data),.re(pop),.ra(rp),.rd(data));
end else begin: hybrid
 // Equal halves avoid wide address subtraction. Keep all 8192 PCM samples.
 wire [31:0] head_q,tail_q;reg read_tail;
 always @(posedge clk)if(pop)read_tail<=rp[AW-1];
 photo_audio_word_ram #(.ADDR(AW-1),.IMPLEMENT("32K")) head(
 .clk(clk),.we(push && !wp[AW-1]),.wa(wp[AW-2:0]),.wd(write_data),
 .re(pop && !rp[AW-1]),.ra(rp[AW-2:0]),.rd(head_q));
 photo_audio_word_ram #(.ADDR(AW-1),.IMPLEMENT("9K")) tail(
 .clk(clk),.we(push && wp[AW-1]),.wa(wp[AW-2:0]),.wd(write_data),
 .re(pop && rp[AW-1]),.ra(rp[AW-2:0]),.rd(tail_q));
 assign data=read_tail ? tail_q:head_q;
end endgenerate
always @(posedge clk or posedge rst)begin
 if(rst)begin wp<=0;rp<=0;used<=0;end
 else begin
  if(push)wp<=wp+1'b1;if(pop)rp<=rp+1'b1;
  case({push,pop})2'b10:used<=used+1'b1;2'b01:used<=used-1'b1;default:;endcase
 end
end
endmodule
