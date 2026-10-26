// Commands: 00 skip unchanged pairs, 01 literal pairs, 10 repeated pair.
// Writes are accepted at their unmasked beat; completion waits for bus drain.
module delta_decoder #(parameter WAIT_DRAIN=0,parameter EXTERNAL_CRC=0)(
 input clk,input rst,input start,input target,
 input [20:0] encoded_words,input [31:0] stream_data,input stream_valid,output stream_pop,
 output patch_valid,output [20:0] patch_addr,output [31:0] patch_data,input patch_ready,
 output reg done,output reg error,output reg busy,
 output reg [3:0] error_kind,output [95:0] fault_data,output [31:0] encoded_crc,input patch_drained,
 input [31:0] external_crc
);
localparam IDLE=0,CMD=1,LITERAL=2,FILL_WORD=3,FILL=4,FINISH=5;
reg [2:0] state;reg [20:0] remaining;reg [16:0] cursor,run;
reg [31:0] fill_data;reg target_latch;
reg [31:0] crc,consumed,fault_word,fault_index,fault_cursor,last_command;
assign encoded_crc=(EXTERNAL_CRC ? external_crc : crc)^32'hffffffff;
assign fault_data={fault_cursor,fault_index,fault_word};
function [31:0] crc_word;
 input [31:0] old,word;
 reg [31:0] mix;
 reg [64:0] terms;
 begin
  mix=old^word;
  terms[0]=mix[0]^mix[22];
  terms[1]=mix[2]^mix[7];
  terms[2]=mix[1]^mix[23];
  terms[3]=mix[3]^mix[6];
  terms[4]=mix[4]^terms[0];
  terms[5]=mix[5]^mix[8];
  terms[6]=mix[17]^mix[24];
  terms[7]=mix[18]^mix[25];
  terms[8]=mix[10]^mix[26];
  terms[9]=mix[11]^mix[27];
  terms[10]=mix[12]^mix[28];
  terms[11]=mix[13]^mix[29];
  terms[12]=mix[14]^mix[30];
  terms[13]=mix[15]^mix[31];
  terms[14]=mix[20]^terms[1];
  terms[15]=mix[9]^mix[21];
  terms[16]=mix[16]^terms[4];
  terms[17]=mix[7]^mix[19];
  terms[18]=mix[5]^terms[13];
  terms[19]=mix[24]^mix[28];
  terms[20]=mix[25]^mix[29];
  terms[21]=terms[2]^terms[8];
  terms[22]=mix[0]^terms[10];
  terms[23]=mix[16]^mix[23];
  terms[24]=terms[6]^terms[11];
  terms[25]=terms[7]^terms[12];
  terms[26]=mix[19]^mix[27];
  terms[27]=mix[8]^mix[26];
  terms[28]=mix[3]^mix[4];
  terms[29]=terms[1]^terms[15];
  terms[30]=terms[5]^terms[6];
  terms[31]=mix[2]^mix[9];
  terms[32]=terms[3]^terms[5];
  terms[33]=mix[9]^mix[11];
  terms[34]=mix[6]^mix[30];
  terms[35]=mix[31]^terms[9];
  terms[36]=mix[13]^terms[4];
  terms[37]=terms[0]^terms[18];
  terms[38]=terms[2]^terms[14];
  terms[39]=terms[3]^terms[16];
  terms[40]=mix[10]^terms[31];
  terms[41]=mix[4]^terms[17];
  terms[42]=mix[5]^terms[21];
  terms[43]=mix[4]^terms[14];
  terms[44]=mix[12]^terms[5];
  terms[45]=mix[24]^terms[8];
  terms[46]=terms[9]^terms[34];
  terms[47]=mix[25]^terms[22];
  terms[48]=terms[35]^terms[47];
  terms[49]=mix[3]^mix[20];
  terms[50]=mix[14]^terms[23];
  terms[51]=mix[1]^mix[21];
  terms[52]=mix[10]^mix[15];
  terms[53]=terms[12]^terms[24];
  terms[54]=terms[16]^terms[25];
  terms[55]=mix[17]^terms[36];
  terms[56]=mix[14]^mix[18];
  terms[57]=mix[22]^terms[26];
  terms[58]=mix[15]^terms[19];
  terms[59]=mix[3]^mix[21];
  terms[60]=terms[20]^terms[30];
  terms[61]=mix[31]^terms[26];
  terms[62]=mix[2]^terms[10];
  terms[63]=mix[30]^terms[7];
  terms[64]=mix[28]^terms[12];
  crc_word[0]=terms[27]^terms[38]^terms[39];
  crc_word[1]=mix[27]^terms[2]^terms[28]^terms[29]^terms[30];
  crc_word[2]=terms[4]^terms[7]^terms[19]^terms[32]^terms[40];
  crc_word[3]=terms[3]^terms[20]^terms[33]^terms[41]^terms[42];
  crc_word[4]=terms[43]^terms[44]^terms[45]^terms[46];
  crc_word[5]=mix[7]^mix[13]^terms[15]^terms[32]^terms[48];
  crc_word[6]=terms[11]^terms[22]^terms[40]^terms[49]^terms[50];
  crc_word[7]=mix[11]^terms[28]^terms[51]^terms[52]^terms[53];
  crc_word[8]=mix[2]^mix[11]^mix[12]^terms[18]^terms[54];
  crc_word[9]=mix[19]^terms[13]^terms[14]^terms[44]^terms[55];
  crc_word[10]=mix[5]^mix[26]^terms[29]^terms[36]^terms[56];
  crc_word[11]=mix[14]^terms[2]^terms[32]^terms[52]^terms[57];
  crc_word[12]=mix[6]^terms[23]^terms[33]^terms[43]^terms[58];
  crc_word[13]=mix[0]^mix[7]^mix[10]^mix[12]^mix[16]^terms[59]^terms[60];
  crc_word[14]=mix[1]^terms[7]^terms[27]^terms[33]^terms[34]^terms[55];
  crc_word[15]=mix[9]^mix[12]^terms[1]^terms[42]^terms[56]^terms[61];
  crc_word[16]=mix[13]^mix[16]^mix[22]^terms[9]^terms[21]^terms[41]^terms[58];
  crc_word[17]=mix[20]^terms[9]^terms[50]^terms[60]^terms[62];
  crc_word[18]=mix[15]^mix[26]^terms[3]^terms[15]^terms[22]^terms[24]^terms[63];
  crc_word[19]=mix[1]^mix[27]^mix[31]^terms[8]^terms[11]^terms[17]^terms[54];
  crc_word[20]=mix[17]^terms[9]^terms[17]^terms[18]^terms[39]^terms[64];
  crc_word[21]=mix[3]^mix[17]^mix[18]^mix[26]^mix[29]^terms[37]^terms[62];
  crc_word[22]=mix[18]^mix[30]^terms[11]^terms[14]^terms[27]^terms[57];
  crc_word[23]=mix[0]^mix[8]^mix[23]^terms[15]^terms[49]^terms[61]^terms[64];
  crc_word[24]=mix[8]^mix[29]^terms[3]^terms[8]^terms[13]^terms[19]^terms[23]^terms[29];
  crc_word[25]=mix[20]^terms[6]^terms[20]^terms[21]^terms[31]^terms[46];
  crc_word[26]=terms[1]^terms[10]^terms[35]^terms[45]^terms[59]^terms[63];
  crc_word[27]=mix[6]^mix[16]^mix[19]^terms[11]^terms[38]^terms[48];
  crc_word[28]=mix[6]^mix[21]^mix[23]^terms[10]^terms[16]^terms[53];
  crc_word[29]=mix[7]^terms[2]^terms[24]^terms[25]^terms[37];
  crc_word[30]=mix[20]^mix[22]^mix[24]^terms[13]^terms[17]^terms[25]^terms[28];
  crc_word[31]=mix[19]^mix[25]^terms[1]^terms[3]^terms[37]^terms[51];
 end
endfunction
wire [1:0] kind=stream_data[31:30];wire [29:0] count=stream_data[29:0];
assign patch_valid=busy && ((state==LITERAL && stream_valid)||(state==FILL));
assign patch_addr=(target_latch ? 21'd115200 : 21'd0)+cursor;
assign patch_data=state==FILL ? fill_data : stream_data;
assign stream_pop=busy && stream_valid &&
 ((state==CMD && remaining!=0)||(state==FILL_WORD && remaining!=0)||
  (state==LITERAL && remaining!=0 && patch_ready));
always @(posedge clk)begin
 if(rst)begin state<=IDLE;remaining<=0;cursor<=0;run<=0;fill_data<=0;
  target_latch<=0;done<=0;error<=0;busy<=0;error_kind<=0;
  crc<=32'hffffffff;consumed<=0;fault_word<=0;fault_index<=0;fault_cursor<=0;last_command<=0;end
 else begin
  done<=0;
  if(start && !busy)begin remaining<=encoded_words;cursor<=0;run<=0;
   target_latch<=target;error<=0;busy<=1;state<=CMD;error_kind<=0;
   crc<=32'hffffffff;consumed<=0;fault_word<=0;fault_index<=0;fault_cursor<=0;last_command<=0;end
  else if(busy)begin
   if(stream_pop)begin
    if(!EXTERNAL_CRC)crc<=crc_word(crc,stream_data);
    consumed<=consumed+1'b1;
   end
   case(state)
   CMD:begin
    if(remaining==0)begin
     if(cursor==115200)begin state<=FINISH;end
     else begin error<=1;error_kind<=6;busy<=0;state<=IDLE;
      fault_word<=last_command;fault_index<=consumed;fault_cursor<={15'd0,cursor};end
    end else if(stream_valid)begin
     remaining<=remaining-1'b1;last_command<=stream_data;
     if(kind==3 || count==0 || count>115200-cursor ||
        (kind==1 && count>remaining-1) || (kind==2 && remaining<2))begin
      error<=1;busy<=0;state<=IDLE;
      error_kind<=kind==3 ? 4'd2 : count==0 ? 4'd1 : count>115200-cursor ? 4'd3 :
                   kind==1 && count>remaining-1 ? 4'd4 : 4'd5;
      fault_word<=stream_data;fault_index<=consumed;fault_cursor<={15'd0,cursor};
     end else if(kind==0)begin cursor<=cursor+count[16:0];end
     else begin run<=count[16:0];state<=kind==1 ? LITERAL : FILL_WORD;end
    end
   end
   FILL_WORD:if(stream_valid)begin fill_data<=stream_data;remaining<=remaining-1'b1;state<=FILL;end
   FILL:if(patch_ready)begin cursor<=cursor+1'b1;run<=run-1'b1;if(run==1)state<=CMD;end
   LITERAL:if(stream_valid && patch_ready)begin
    cursor<=cursor+1'b1;remaining<=remaining-1'b1;run<=run-1'b1;if(run==1)state<=CMD;
   end
   FINISH:if(!WAIT_DRAIN || patch_drained)begin busy<=0;done<=1;state<=IDLE;end
   endcase
  end
 end
end
endmodule
