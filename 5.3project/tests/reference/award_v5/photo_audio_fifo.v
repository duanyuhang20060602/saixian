module photo_audio_fifo_ref #(parameter DEPTH=8192,AW=13)(
 input clk,rst,input write_en,input [31:0] write_data,input read_en,
 output reg [31:0] data,output empty,full,output reg [AW:0] used
);
reg [31:0] memory[0:DEPTH-1]; /* fehdl force_ram=1, ram_style="bram" */
reg [AW-1:0] wp,rp;
wire push=write_en && !full,pop=read_en && !empty;
assign empty=used==0;assign full=used==DEPTH;
always @(posedge clk)begin
 if(push)memory[wp]<=write_data;
 if(pop)data<=memory[rp];
end
always @(posedge clk or posedge rst)begin
 if(rst)begin wp<=0;rp<=0;used<=0;end
 else begin
  if(push)wp<=wp+1'b1;if(pop)rp<=rp+1'b1;
  case({push,pop})2'b10:used<=used+1'b1;2'b01:used<=used-1'b1;default:;endcase
 end
end
endmodule
